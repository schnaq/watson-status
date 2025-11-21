import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var reminderTimer: Timer?
    var lastTrackingState: Bool = false
    var idleStartTime: Date?
    var lastReminderTime: Date?

    let reminderIntervalMinutes: Double = 5

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        updateStatus()

        // Poll watson status every 5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }

        // Check for idle reminder every 30 seconds
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkIdleReminder()
        }
    }

    func updateStatus() {
        let status = getWatsonStatus()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let button = self.statusItem.button {
                if let (project, elapsed) = status {
                    button.title = "⏱ \(project) (\(elapsed))"
                    self.idleStartTime = nil
                } else {
                    button.title = "⏸ Watson"
                    if self.lastTrackingState && self.idleStartTime == nil {
                        self.idleStartTime = Date()
                    }
                }
            }

            self.lastTrackingState = status != nil
            self.buildMenu(isTracking: status != nil)
        }
    }

    func getWatsonStatus() -> (String, String)? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "watson status"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Parse: "Project foo [tag1 tag2] started 1h 30m ago (2024-01-01 10:00:00+0100)"
            if output.starts(with: "Project ") {
                let parts = output.components(separatedBy: " started ")
                if parts.count >= 2 {
                    var project = parts[0].replacingOccurrences(of: "Project ", with: "")
                    // Remove tags in brackets
                    if let bracketRange = project.range(of: " \\[.*\\]", options: .regularExpression) {
                        project = project.replacingCharacters(in: bracketRange, with: "")
                    }

                    var elapsed = parts[1]
                    if let agoRange = elapsed.range(of: " ago") {
                        elapsed = String(elapsed[..<agoRange.lowerBound])
                    }

                    return (project, elapsed)
                }
            }
        } catch {}

        return nil
    }

    func buildMenu(isTracking: Bool) {
        let menu = NSMenu()

        if isTracking {
            let stopItem = NSMenuItem(title: "Stop Tracking", action: #selector(stopTracking), keyEquivalent: "s")
            stopItem.target = self
            menu.addItem(stopItem)
        } else {
            let notTrackingItem = NSMenuItem(title: "Not tracking", action: nil, keyEquivalent: "")
            notTrackingItem.isEnabled = false
            menu.addItem(notTrackingItem)
        }

        menu.addItem(NSMenuItem.separator())

        let statsItem = NSMenuItem(title: "Today's Stats", action: #selector(showStats), keyEquivalent: "t")
        statsItem.target = self
        menu.addItem(statsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc func stopTracking() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "watson stop"]
        try? process.run()
        process.waitUntilExit()
        updateStatus()
    }

    @objc func showStats() {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "watson report --day"]
        process.standardOutput = pipe
        process.standardError = pipe

        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? "No data"

        let alert = NSAlert()
        alert.messageText = "Today's Time"
        alert.informativeText = output
        alert.alertStyle = .informational
        alert.runModal()
    }

    func checkIdleReminder() {
        guard idleStartTime != nil else { return }
        guard !lastTrackingState else { return }

        let idleMinutes = Date().timeIntervalSince(idleStartTime!) / 60

        // Only remind if not tracking for 5+ min and system is active
        if idleMinutes >= reminderIntervalMinutes && !isSystemIdle() {
            // Don't spam - wait at least 5 min between reminders
            if let last = lastReminderTime, Date().timeIntervalSince(last) < 300 {
                return
            }
            sendReminder()
            lastReminderTime = Date()
        }
    }

    func isSystemIdle() -> Bool {
        // Check if system has been idle (no user input) for more than 2 minutes
        let idleTime = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved)
        return idleTime > 120
    }

    func sendReminder() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Watson"
            alert.informativeText = "Du trackst gerade keine Zeit!"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

// Main entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
