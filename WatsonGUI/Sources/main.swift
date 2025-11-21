import AppKit

// Global references
var statusItem: NSStatusItem!
var timer: Timer?
var reminderTimer: Timer?
var lastTrackingState: Bool = false
var idleStartTime: Date?
var lastReminderTime: Date?
let reminderIntervalMinutes: Double = 5

class MenuHandler: NSObject {
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

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

let handler = MenuHandler()

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

                return (project, elapsed)
            }
        }
    } catch {}

    return nil
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

    if let (project, elapsed) = status {
        statusItem.button?.title = "⏱ \(project) (\(elapsed))"
        idleStartTime = nil
    } else {
        statusItem.button?.title = "⏸ Watson"
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

statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.title = "⏸ Watson"
buildMenu(isTracking: false)
updateStatus()

timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
    updateStatus()
}

reminderTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
    checkIdleReminder()
}

app.run()
