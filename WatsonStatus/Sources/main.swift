import AppKit

// Global references
var statusItem: NSStatusItem!
var timer: Timer?
var reminderTimer: Timer?
var lastTrackingState: Bool = false
var idleStartTime: Date?
var lastReminderTime: Date?
var recentProjects: [(project: String, tags: [String])] = []
let reminderIntervalMinutes: Double = 5
var watsonPath: String = ""

func findWatsonPath() -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-l", "-c", "which watson"]
    process.standardOutput = pipe
    try? process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "/opt/homebrew/bin/watson"
}

class MenuHandler: NSObject {
    @objc func stopTracking() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "\(watsonPath) stop"]
        try? process.run()
        process.waitUntilExit()
        updateStatus()
    }

    @objc func showStats() {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "\(watsonPath) report --day"]
        process.standardOutput = pipe
        process.standardError = pipe

        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? "No data"

        // Create a monospace text view for code-like display
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 450, height: 300))
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor.white
        textView.string = output
        textView.textContainerInset = NSSize(width: 10, height: 10)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 450, height: 300))
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let alert = NSAlert()
        alert.messageText = "Today's Time"
        alert.alertStyle = .informational
        alert.accessoryView = scrollView
        alert.runModal()
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    @objc func handleSleep() {
        // Stop watson when Mac goes to sleep
        if lastTrackingState {
            stopTracking()
        }
    }

    @objc func startProject(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? (String, [String]) else { return }
        let project = info.0
        let tags = info.1
        let tagStr = tags.map { "+\($0)" }.joined(separator: " ")
        let cmd = "\(watsonPath) start \(project) \(tagStr)".trimmingCharacters(in: .whitespaces)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", cmd]
        try? process.run()
        process.waitUntilExit()
        updateStatus()
    }
}

let handler = MenuHandler()

// Register for sleep notification
NSWorkspace.shared.notificationCenter.addObserver(
    handler,
    selector: #selector(MenuHandler.handleSleep),
    name: NSWorkspace.willSleepNotification,
    object: nil
)

func getWatsonStatus() -> (String, String)? {
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-l", "-c", "\(watsonPath) status"]
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if output.starts(with: "Project ") {
            let parts = output.components(separatedBy: " started ")
            if parts.count >= 2 {
                var project = parts[0].replacingOccurrences(of: "Project ", with: "")
                if let bracketRange = project.range(of: " \\[.*\\]", options: .regularExpression) {
                    project = project.replacingCharacters(in: bracketRange, with: "")
                }

                var elapsed = parts[1]
                if let agoRange = elapsed.range(of: " ago") {
                    elapsed = String(elapsed[..<agoRange.lowerBound])
                }
                // Shorten: "14 minutes" -> "14m", "1 hour 30 minutes" -> "1h 30m"
                elapsed = elapsed
                    .replacingOccurrences(of: " hours", with: "h")
                    .replacingOccurrences(of: " hour", with: "h")
                    .replacingOccurrences(of: " minutes", with: "m")
                    .replacingOccurrences(of: " minute", with: "m")
                    .replacingOccurrences(of: " seconds", with: "s")
                    .replacingOccurrences(of: " second", with: "s")

                return (project, elapsed)
            }
        }
    } catch {}

    return nil
}

func getRecentProjects() -> [(project: String, tags: [String])] {
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-l", "-c", "\(watsonPath) log --json"]
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            var seen = Set<String>()
            var results: [(String, [String])] = []
            for entry in json {
                if let project = entry["project"] as? String {
                    let tags = entry["tags"] as? [String] ?? []
                    let key = "\(project)|\(tags.joined(separator: ","))"
                    if !seen.contains(key) {
                        seen.insert(key)
                        results.append((project, tags))
                        if results.count >= 10 { break }
                    }
                }
            }
            return results
        }
    } catch {}

    return []
}

func buildMenu(isTracking: Bool) {
    let menu = NSMenu()

    if isTracking {
        let stopItem = NSMenuItem(title: "Stop Tracking", action: #selector(MenuHandler.stopTracking), keyEquivalent: "s")
        stopItem.target = handler
        menu.addItem(stopItem)
    } else {
        let notTrackingItem = NSMenuItem(title: "Not tracking", action: nil, keyEquivalent: "")
        notTrackingItem.isEnabled = false
        menu.addItem(notTrackingItem)
    }

    menu.addItem(NSMenuItem.separator())

    // Recent projects submenu
    if !recentProjects.isEmpty {
        let startMenu = NSMenu()
        for entry in recentProjects {
            let title = entry.tags.isEmpty ? entry.project : "\(entry.project) [\(entry.tags.joined(separator: ", "))]"
            let item = NSMenuItem(title: title, action: #selector(MenuHandler.startProject(_:)), keyEquivalent: "")
            item.target = handler
            item.representedObject = (entry.project, entry.tags)
            startMenu.addItem(item)
        }
        let startItem = NSMenuItem(title: "Start Project", action: nil, keyEquivalent: "")
        startItem.submenu = startMenu
        menu.addItem(startItem)

        menu.addItem(NSMenuItem.separator())
    }

    let statsItem = NSMenuItem(title: "Today's Stats", action: #selector(MenuHandler.showStats), keyEquivalent: "t")
    statsItem.target = handler
    menu.addItem(statsItem)

    menu.addItem(NSMenuItem.separator())

    let quitItem = NSMenuItem(title: "Quit", action: #selector(MenuHandler.quitApp), keyEquivalent: "q")
    quitItem.target = handler
    menu.addItem(quitItem)

    statusItem.menu = menu
}

func updateStatus() {
    let status = getWatsonStatus()
    recentProjects = getRecentProjects()

    if let (project, elapsed) = status {
        let title = " \(project) (\(elapsed))"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.systemGreen
        ]
        statusItem.button?.attributedTitle = NSAttributedString(string: title, attributes: attrs)
        statusItem.button?.image = NSImage(systemSymbolName: "stopwatch.fill", accessibilityDescription: "Tracking")
        statusItem.button?.image?.isTemplate = true
        idleStartTime = nil
    } else {
        let title = " Watson"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.systemOrange
        ]
        statusItem.button?.attributedTitle = NSAttributedString(string: title, attributes: attrs)
        statusItem.button?.image = NSImage(systemSymbolName: "stopwatch", accessibilityDescription: "Paused")
        statusItem.button?.image?.isTemplate = true
        if lastTrackingState && idleStartTime == nil {
            idleStartTime = Date()
        }
    }

    lastTrackingState = status != nil
    buildMenu(isTracking: status != nil)
}

func checkIdleReminder() {
    guard let idleStart = idleStartTime else { return }
    guard !lastTrackingState else { return }

    let idleMinutes = Date().timeIntervalSince(idleStart) / 60

    if idleMinutes >= reminderIntervalMinutes && !isSystemIdle() {
        if let last = lastReminderTime, Date().timeIntervalSince(last) < 300 {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Watson"
        alert.informativeText = "Du trackst gerade keine Zeit!"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()

        lastReminderTime = Date()
    }
}

func isSystemIdle() -> Bool {
    let idleTime = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved)
    return idleTime > 120
}

// Main
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

watsonPath = findWatsonPath()

statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
let initAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemOrange]
statusItem.button?.attributedTitle = NSAttributedString(string: " Watson", attributes: initAttrs)
statusItem.button?.image = NSImage(systemSymbolName: "stopwatch", accessibilityDescription: "Paused")
statusItem.button?.image?.isTemplate = true
statusItem.button?.imagePosition = .imageLeft
buildMenu(isTracking: false)
updateStatus()

timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
    updateStatus()
}

reminderTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
    checkIdleReminder()
}

app.run()
