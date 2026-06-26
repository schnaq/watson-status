import AppKit
import Carbon.HIToolbox
import UserNotifications

// MARK: - Configuration
let reminderIntervalMinutes: Double = 5
let reminderCooldownSeconds: Double = 300
let activeWithinSeconds: Double = 120
let watsonSearchPaths = ["/opt/homebrew/bin/watson", "/usr/local/bin/watson", "/usr/bin/watson"]

// MARK: - Command registry
/// A user action that can be invoked from BOTH a menu item and a global hotkey, so the two
/// stay a single source of truth. Adding a new shortcut means adding one `Command`.
struct Command {
    let id: UInt32                 // stable id; also the Carbon EventHotKeyID
    let title: String
    let menuKeyEquivalent: String  // in-menu accelerator (only active while the menu is open)
    let key: KeyCombo?             // global system-wide hotkey; nil = menu only
    let run: () -> Void
}

// MARK: - App Controller
/// Owns all app state, the status item, the timers and the command/hotkey wiring. Having a
/// single owner gives global-hotkey registration a clear lifecycle instead of scattered globals.
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    // UI + timers
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var timer: Timer?
    private var reminderTimer: Timer?
    private let hotKeyCenter = HotKeyCenter()
    private var isPresentingModal = false

    // Tracking state machine
    private var watsonPath = ""
    private var recentProjects: [(project: String, tags: [String])] = []
    private var lastTrackingState = false
    private var idleStartTime: Date?
    private var lastReminderTime: Date?
    private var notificationPermissionGranted = false

    // Reused on the hot path instead of being rebuilt on every status read. Pinned to a POSIX
    // locale so a non-Gregorian system calendar (e.g. Buddhist, Persian) cannot misread the year.
    // Two variants: with timezone offset (preferred) and an offset-less local-time fallback.
    private let startTimestampFormatterWithZone: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd HH:mm:ssZ"
        return formatter
    }()
    private let startTimestampFormatterLocal: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd HH:mm:ss"
        return formatter
    }()

    // MARK: Commands
    /// Global hotkeys use Ctrl+Opt+Cmd + letter — uncommon combos unlikely to collide with
    /// system or app shortcuts. The same combos are NOT the menu accelerators (those only fire
    /// while the menu is open); both are kept intentionally.
    private lazy var commands: [Command] = [
        Command(id: 1, title: "Stop Tracking", menuKeyEquivalent: "s",
                key: KeyCombo(kVK_ANSI_S, controlKey | optionKey | cmdKey),
                run: { [weak self] in self?.stopTracking() }),
        Command(id: 2, title: "Start Last Project", menuKeyEquivalent: "",
                key: KeyCombo(kVK_ANSI_L, controlKey | optionKey | cmdKey),
                run: { [weak self] in self?.startLastProject() }),
        Command(id: 3, title: "Today's Stats", menuKeyEquivalent: "t",
                key: KeyCombo(kVK_ANSI_T, controlKey | optionKey | cmdKey),
                run: { [weak self] in self?.showReport(title: "Today's Time", arguments: ["report", "--day"]) }),
        Command(id: 4, title: "Yesterday's Stats", menuKeyEquivalent: "y",
                key: KeyCombo(kVK_ANSI_Y, controlKey | optionKey | cmdKey),
                run: { [weak self] in self?.showYesterdayStats() }),
    ]

    private func command(id: UInt32) -> Command? { commands.first { $0.id == id } }

    // MARK: Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        watsonPath = findWatsonPath()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setTitle("⏱ —", color: .systemOrange)

        // The dropdown rebuilds its contents lazily via menuNeedsUpdate(_:) each time it opens, so
        // the recent-projects list is always current without polling `watson log` on the 5s timer.
        menu.delegate = self
        statusItem.menu = menu

        // Stop tracking on real system sleep only — NOT screensDidSleep: display sleep fires on
        // the screen-off timeout while the user is still working and would cut sessions short.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleSleep),
            name: NSWorkspace.willSleepNotification, object: nil)

        requestNotificationsIfNeeded()
        hotKeyCenter.register(commands)

        updateStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.updateStatus() }
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.checkIdleReminder() }
    }

    // MARK: Watson interaction
    /// Runs the watson binary directly (no shell). This avoids the login-shell overhead on the
    /// hot path AND prevents shell injection from project/tag names containing spaces or
    /// metacharacters, since arguments are passed as a vector rather than a re-parsed string.
    private func runWatson(_ arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: watsonPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            NSLog("WatsonStatus: failed to run watson \(arguments): \(error)")
            return ""
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func findWatsonPath() -> String {
        for path in watsonSearchPaths where FileManager.default.fileExists(atPath: path) {
            return path
        }
        // Fall back to PATH resolution via a login shell. Runs once at startup only, so the
        // login-shell cost is irrelevant here.
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which watson"]
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let found = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return found.isEmpty ? watsonSearchPaths[0] : found
    }

    private func getWatsonStatus() -> (project: String, elapsed: String)? {
        let output = runWatson(["status"])
        guard output.starts(with: "Project "), let startedRange = output.range(of: " started ") else { return nil }

        var project = String(output[..<startedRange.lowerBound]).replacingOccurrences(of: "Project ", with: "")
        // Strip only the trailing " [tags]" Watson appends; end-anchored and non-greedy so
        // brackets inside the project name itself (e.g. "feature [beta]") are preserved.
        project = project.replacingOccurrences(of: " \\[[^\\]]*\\]$", with: "", options: .regularExpression)

        var elapsed = "?"
        // Prefer the timestamp WITH its timezone offset (e.g. 2025.11.21 15:29:39+0100) so elapsed
        // stays correct across timezone changes and DST boundaries; fall back to an offset-less
        // timestamp read as local time if a watson build ever omits the offset.
        var startDate: Date?
        if let tsMatch = output.range(of: "\\d{4}\\.\\d{2}\\.\\d{2} \\d{2}:\\d{2}:\\d{2}[+-]\\d{4}", options: .regularExpression) {
            startDate = startTimestampFormatterWithZone.date(from: String(output[tsMatch]))
        } else if let tsMatch = output.range(of: "\\d{4}\\.\\d{2}\\.\\d{2} \\d{2}:\\d{2}:\\d{2}", options: .regularExpression) {
            startDate = startTimestampFormatterLocal.date(from: String(output[tsMatch]))
        }
        if let startDate = startDate {
            let seconds = Int(Date().timeIntervalSince(startDate))
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            elapsed = hours > 0 ? "\(hours)h\(minutes)m" : "\(minutes)m"
        }
        return (project, elapsed)
    }

    private func getRecentProjects() -> [(project: String, tags: [String])] {
        let output = runWatson(["log", "--json"])
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        var seen = Set<String>()
        var results: [(String, [String])] = []
        // `watson log --json` is oldest-first; iterate in reverse so the de-duped first 10 are
        // the genuinely most-recent project/tag combinations rather than ancient history.
        for entry in json.reversed() {
            guard let project = entry["project"] as? String else { continue }
            let tags = entry["tags"] as? [String] ?? []
            let key = "\(project)|\(tags.joined(separator: ","))"
            if seen.insert(key).inserted {
                results.append((project, tags))
                if results.count >= 10 { break }
            }
        }
        return results
    }

    // MARK: Actions
    private func stopTracking() {
        _ = runWatson(["stop"])
        updateStatus()
    }

    private func startProject(_ project: String, tags: [String]) {
        _ = runWatson(["start", project] + tags.map { "+\($0)" })
        updateStatus()
    }

    private func startLastProject() {
        // Fetch fresh rather than trusting the cached list: the hotkey can fire before the menu
        // has ever been opened (which is what populates recentProjects), and it should always
        // start the genuinely most-recent project.
        guard let last = getRecentProjects().first else { return }
        startProject(last.project, tags: last.tags)
    }

    @objc private func startProjectFromMenu(_ sender: NSMenuItem) {
        guard let (project, tags) = sender.representedObject as? (String, [String]) else { return }
        startProject(project, tags: tags)
    }

    @objc private func runCommandFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UInt32, let cmd = command(id: id) else { return }
        cmd.run()
    }

    private func showYesterdayStats() {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: yesterday)
        showReport(title: "Yesterday's Time", arguments: ["report", "--from", day, "--to", day])
    }

    /// Shared report window — runs a watson report and shows it in a scrollable modal. New
    /// report shortcuts become one `Command` each instead of a copy of this view code.
    private func showReport(title: String, arguments: [String]) {
        // A global hotkey can fire while a report is already open; refuse to stack modals.
        guard !isPresentingModal else { return }
        isPresentingModal = true
        defer { isPresentingModal = false }

        let output = runWatson(arguments)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 450, height: 300))
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .white
        textView.string = output
        textView.textContainerInset = NSSize(width: 10, height: 10)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 450, height: 300))
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let alert = NSAlert()
        alert.messageText = title
        alert.accessoryView = scrollView
        // Accessory (LSUIElement) apps have no active window; bring the alert forward so a
        // hotkey-triggered report is not buried behind other apps.
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func handleSleep() {
        // Re-check live status rather than trusting cached state.
        if runWatson(["status"]).starts(with: "Project ") {
            NSLog("WatsonStatus: system sleep detected — stopping tracking")
            _ = runWatson(["stop"])
            updateStatus()
        }
    }

    @objc private func checkNotifications() {
        checkNotificationPermission { [weak self] granted in
            guard let self, !self.isPresentingModal else { return }
            self.isPresentingModal = true
            defer { self.isPresentingModal = false }

            let alert = NSAlert()
            alert.messageText = "Notification Settings"
            if granted {
                alert.informativeText = "✅ Notifications are enabled.\n\nYou will receive reminders when you're not tracking time."
                alert.addButton(withTitle: "OK")
            } else {
                alert.informativeText = "⚠️ Notifications are disabled.\n\nWatsonStatus cannot remind you to track time without notification permission.\n\nTo enable notifications:\n1. Click 'Open Settings' below\n2. Find WatsonStatus in the list\n3. Enable 'Allow Notifications'"
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Cancel")
            }

            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            if !granted && response == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: Notifications
    private func checkNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                let granted = settings.authorizationStatus == .authorized
                self?.notificationPermissionGranted = granted
                completion(granted)
            }
        }
    }

    private func requestNotificationsIfNeeded() {
        checkNotificationPermission { [weak self] granted in
            guard !granted else {
                print("✅ Notification permission granted")
                return
            }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { newGranted, error in
                DispatchQueue.main.async {
                    if let error = error { print("Error requesting notification permission: \(error)") }
                    self?.notificationPermissionGranted = newGranted
                    if !newGranted {
                        print("⚠️  Notification permission denied. Reminders will not work.")
                        print("    Enable in: System Settings → Notifications → WatsonStatus")
                    }
                }
            }
        }
    }

    // MARK: UI
    private func setTitle(_ text: String, color: NSColor) {
        statusItem.button?.attributedTitle = NSAttributedString(string: text, attributes: [.foregroundColor: color])
    }

    private func menuItem(for command: Command) -> NSMenuItem {
        let item = NSMenuItem(title: command.title,
                              action: #selector(runCommandFromMenu(_:)),
                              keyEquivalent: command.menuKeyEquivalent)
        item.target = self
        item.representedObject = command.id
        return item
    }

    // MARK: NSMenuDelegate
    /// Called by AppKit each time the status-bar menu is about to open: re-reads the recent
    /// projects and current tracking state so the dropdown is always fresh, without the 5s timer
    /// ever having to poll `watson log`.
    func menuNeedsUpdate(_ menu: NSMenu) {
        recentProjects = getRecentProjects()
        populateMenu(menu, isTracking: getWatsonStatus() != nil)
    }

    private func populateMenu(_ menu: NSMenu, isTracking: Bool) {
        menu.removeAllItems()

        if isTracking, let stop = command(id: 1) {
            menu.addItem(menuItem(for: stop))
        } else {
            let item = NSMenuItem(title: "Not tracking", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        if !recentProjects.isEmpty {
            let submenu = NSMenu()
            for (project, tags) in recentProjects {
                let title = tags.isEmpty ? project : "\(project) [\(tags.joined(separator: ", "))]"
                let item = NSMenuItem(title: title, action: #selector(startProjectFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = (project, tags)
                submenu.addItem(item)
            }
            let startItem = NSMenuItem(title: "Start Project", action: nil, keyEquivalent: "")
            startItem.submenu = submenu
            menu.addItem(startItem)
            menu.addItem(.separator())
        }

        if let today = command(id: 3) { menu.addItem(menuItem(for: today)) }
        if let yesterday = command(id: 4) { menu.addItem(menuItem(for: yesterday)) }

        menu.addItem(.separator())

        let notifItem = NSMenuItem(title: "Notification Settings…", action: #selector(checkNotifications), keyEquivalent: "")
        notifItem.target = self
        menu.addItem(notifItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: Status updates
    /// Refreshes only the menu-bar title and the idle state machine. The 5s timer therefore makes
    /// a single `watson status` call per tick; the dropdown refreshes itself lazily on open (see
    /// menuNeedsUpdate), so the recent-projects list is never stale yet never polled here.
    private func updateStatus() {
        let status = getWatsonStatus()

        if let (project, elapsed) = status {
            setTitle("⏱ \(project) (\(elapsed))", color: .systemGreen)
            idleStartTime = nil
        } else {
            setTitle("⏱ —", color: .systemOrange)
            // Start the idle clock on the tracking→idle edge, or on first launch while idle.
            if lastTrackingState || idleStartTime == nil {
                idleStartTime = Date()
            }
        }

        lastTrackingState = status != nil
    }

    private func checkIdleReminder() {
        guard let idleStart = idleStartTime, !lastTrackingState else { return }
        guard Date().timeIntervalSince(idleStart) / 60 >= reminderIntervalMinutes else { return }

        // Only remind while the user is actually present. Check keyboard AND pointer activity —
        // a user typing without moving the mouse is still active and should be nudged.
        let inputTypes: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
        let secondsSinceInput = inputTypes
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .greatestFiniteMagnitude
        guard secondsSinceInput <= activeWithinSeconds else { return }

        guard lastReminderTime == nil || Date().timeIntervalSince(lastReminderTime!) >= reminderCooldownSeconds else { return }

        guard notificationPermissionGranted else {
            print("Cannot send notification: permission not granted. Enable in System Settings → Notifications → WatsonStatus")
            lastReminderTime = Date() // avoid spamming logs
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Watson"
        content.body = "Hey, don't forget to track your time"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("Error sending notification: \(error)") }
        }

        lastReminderTime = Date()
    }
}

// MARK: - Entry point
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = AppController()
app.delegate = controller
app.run()
