import AppKit
import UserNotifications

// MARK: - Configuration
let reminderIntervalMinutes: Double = 5
let watsonPaths = ["/opt/homebrew/bin/watson", "/usr/local/bin/watson", "/usr/bin/watson"]

// MARK: - State
var statusItem: NSStatusItem!
var timer: Timer?
var reminderTimer: Timer?
var lastTrackingState = false
var idleStartTime: Date?
var lastReminderTime: Date?
var recentProjects: [(project: String, tags: [String])] = []
var watsonPath = ""

// MARK: - Shell Helpers
func runShell(_ command: String) -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-l", "-c", command]
    process.standardOutput = pipe
    process.standardError = pipe
    try? process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func findWatsonPath() -> String {
    for path in watsonPaths {
        if FileManager.default.fileExists(atPath: path) { return path }
    }
    let found = runShell("which watson")
    return found.isEmpty ? watsonPaths[0] : found
}

// MARK: - Watson Commands
func getWatsonStatus() -> (project: String, elapsed: String)? {
    let output = runShell("\(watsonPath) status")
    guard output.starts(with: "Project "), let range = output.range(of: " started ") else { return nil }

    var project = String(output[..<range.lowerBound]).replacingOccurrences(of: "Project ", with: "")
    project = project.replacingOccurrences(of: " \\[.*\\]", with: "", options: .regularExpression)

    // Parse timestamp from output (format: 2025.11.21 15:29:39+0100)
    var elapsed = "?"
    if let tsMatch = output.range(of: "\\d{4}\\.\\d{2}\\.\\d{2} \\d{2}:\\d{2}:\\d{2}", options: .regularExpression) {
        let tsString = String(output[tsMatch])
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd HH:mm:ss"
        if let startDate = formatter.date(from: tsString) {
            let seconds = Int(Date().timeIntervalSince(startDate))
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            if hours > 0 {
                elapsed = "\(hours)h\(minutes)m"
            } else {
                elapsed = "\(minutes)m"
            }
        }
    }

    return (project, elapsed)
}

func getRecentProjects() -> [(project: String, tags: [String])] {
    let output = runShell("\(watsonPath) log --json")
    guard let data = output.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

    var seen = Set<String>()
    var results: [(String, [String])] = []
    for entry in json {
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

// MARK: - Menu Handler
class MenuHandler: NSObject {
    @objc func stopTracking() {
        _ = runShell("\(watsonPath) stop")
        updateStatus()
    }

    @objc func startProject(_ sender: NSMenuItem) {
        guard let (project, tags) = sender.representedObject as? (String, [String]) else { return }
        let tagStr = tags.map { "+\($0)" }.joined(separator: " ")
        _ = runShell("\(watsonPath) start \(project) \(tagStr)")
        updateStatus()
    }

    @objc func showStats() {
        let output = runShell("\(watsonPath) report --day")

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
        alert.messageText = "Today's Time"
        alert.accessoryView = scrollView
        alert.runModal()
    }

    @objc func showYesterdayStats() {
        // Calculate yesterday's date
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let yesterdayStr = formatter.string(from: yesterday)

        let output = runShell("\(watsonPath) report --from \(yesterdayStr) --to \(yesterdayStr)")

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
        alert.messageText = "Yesterday's Time"
        alert.accessoryView = scrollView
        alert.runModal()
    }

    @objc func handleSleep() {
        // Check current Watson status directly instead of relying on cached state
        let output = runShell("\(watsonPath) status")
        if output.starts(with: "Project ") {
            print("Sleep detected - stopping Watson tracking")
            _ = runShell("\(watsonPath) stop")
            updateStatus()
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

let handler = MenuHandler()

// MARK: - UI
func setTitle(_ text: String, color: NSColor) {
    let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color]
    statusItem.button?.attributedTitle = NSAttributedString(string: text, attributes: attrs)
}

func buildMenu(isTracking: Bool) {
    let menu = NSMenu()

    if isTracking {
        let item = NSMenuItem(title: "Stop Tracking", action: #selector(MenuHandler.stopTracking), keyEquivalent: "s")
        item.target = handler
        menu.addItem(item)
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
            let item = NSMenuItem(title: title, action: #selector(MenuHandler.startProject), keyEquivalent: "")
            item.target = handler
            item.representedObject = (project, tags)
            submenu.addItem(item)
        }
        let startItem = NSMenuItem(title: "Start Project", action: nil, keyEquivalent: "")
        startItem.submenu = submenu
        menu.addItem(startItem)
        menu.addItem(.separator())
    }

    let statsItem = NSMenuItem(title: "Today's Stats", action: #selector(MenuHandler.showStats), keyEquivalent: "t")
    statsItem.target = handler
    menu.addItem(statsItem)

    let yesterdayStatsItem = NSMenuItem(title: "Yesterday's Stats", action: #selector(MenuHandler.showYesterdayStats), keyEquivalent: "y")
    yesterdayStatsItem.target = handler
    menu.addItem(yesterdayStatsItem)

    menu.addItem(.separator())

    let quitItem = NSMenuItem(title: "Quit", action: #selector(MenuHandler.quitApp), keyEquivalent: "q")
    quitItem.target = handler
    menu.addItem(quitItem)

    statusItem.menu = menu
}

func updateStatus() {
    recentProjects = getRecentProjects()

    if let (project, elapsed) = getWatsonStatus() {
        setTitle("⏱ \(project) (\(elapsed))", color: .systemGreen)
        idleStartTime = nil
    } else {
        setTitle("⏱ —", color: .systemOrange)
        if lastTrackingState { idleStartTime = Date() }
    }

    let isTracking = getWatsonStatus() != nil
    lastTrackingState = isTracking
    buildMenu(isTracking: isTracking)
}

func checkIdleReminder() {
    guard let idleStart = idleStartTime, !lastTrackingState else { return }
    guard Date().timeIntervalSince(idleStart) / 60 >= reminderIntervalMinutes else { return }
    guard CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved) <= 120 else { return }
    guard lastReminderTime == nil || Date().timeIntervalSince(lastReminderTime!) >= 300 else { return }

    // Send push notification instead of alert
    let content = UNMutableNotificationContent()
    content.title = "Watson"
    content.body = "Hey, don't forget to track your time"
    content.sound = .default

    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
            print("Error sending notification: \(error)")
        }
    }

    lastReminderTime = Date()
}

// MARK: - Main
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Request notification permissions
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
    if let error = error {
        print("Error requesting notification permission: \(error)")
    }
}

watsonPath = findWatsonPath()
statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
setTitle("⏱ —", color: .systemOrange)

// Register for both sleep notifications to ensure we catch the event
NSWorkspace.shared.notificationCenter.addObserver(handler, selector: #selector(MenuHandler.handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
NSWorkspace.shared.notificationCenter.addObserver(handler, selector: #selector(MenuHandler.handleSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)

updateStatus()
timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in updateStatus() }
reminderTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in checkIdleReminder() }

app.run()
