import AppKit
import Foundation
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let engine = AutomationEngine()
    private var settings = AppSettings()
    private var window: NSWindow!
    private var statusItem: NSStatusItem!

    private let statusLabel = NSTextField(labelWithString: "Stopped")
    private let permissionLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(labelWithString: "")
    private let minimumIntervalField = NSTextField(string: "30")
    private let maximumIntervalField = NSTextField(string: "60")
    private let randomIntervalButton = NSButton(checkboxWithTitle: "Random interval", target: nil, action: nil)
    private let keepAwakeButton = NSButton(checkboxWithTitle: "Prevent system sleep while running", target: nil, action: nil)
    private let pauseOnBatteryButton = NSButton(checkboxWithTitle: "Pause on battery", target: nil, action: nil)
    private let autoPauseButton = NSButton(checkboxWithTitle: "Auto-pause when user input is detected", target: nil, action: nil)
    private let autoResumeButton = NSButton(checkboxWithTitle: "Auto-resume after inactivity", target: nil, action: nil)
    private let autoResumeSecondsField = NSTextField(string: "30")
    private let launchAtLoginButton = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)

    private let actionTable = NSTableView()
    private let actionKindPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let actionNameField = NSTextField(string: "")
    private let actionParameterField = NSTextField(string: "")
    private let actionArgumentsField = NSTextField(string: "")
    private let actionTriggerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let actionEnabledButton = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let actionRepeatButton = NSButton(checkboxWithTitle: "Repeat on later intervals", target: nil, action: nil)
    private let repeatLimitField = NSTextField(string: "0")
    private let waitForExitButton = NSButton(checkboxWithTitle: "Wait for command", target: nil, action: nil)
    private let actionHelpLabel = NSTextField(labelWithString: "")
    private let scheduleTable = NSTableView()
    private let scheduleTimeField = NSTextField(string: "09:00")
    private let scheduleWeekdaysField = NSTextField(string: "Sun,Mon,Tue,Wed,Thu,Fri,Sat")
    private let scheduleActionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let blackoutTable = NSTableView()
    private let blackoutTimeField = NSTextField(string: "22:00")
    private let blackoutDurationField = NSTextField(string: "60")
    private let blackoutWeekdaysField = NSTextField(string: "Sun,Mon,Tue,Wed,Thu,Fri,Sat")
    private var selectedActionIndex: Int?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            settings = try SettingsStore.load()
        } catch {
            presentError("Could not load settings at \(SettingsStore.settingsURL.path): \(error.localizedDescription). Defaults are in use; the existing file will not be replaced unless you save.")
            settings = AppSettings()
        }
        engine.configure(settings)
        engine.onStateChanged = { [weak self] state in self?.updateState(state) }
        engine.onError = { [weak self] message in self?.showError(message) }
        buildWindow()
        buildStatusItem()
        populateControls()
        updatePermissionStatus()
        showWindow()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        updatePermissionStatus()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func buildWindow() {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.distribution = .fill
        content.spacing = 8
        content.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)

        let title = NSTextField(labelWithString: "Move Mouse")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        content.addArrangedSubview(title)
        content.addArrangedSubview(statusLabel)

        permissionLabel.textColor = .secondaryLabelColor
        permissionLabel.maximumNumberOfLines = 2
        content.addArrangedSubview(row([permissionLabel, button("Request Accessibility Access", #selector(requestPermission))]))
        content.addArrangedSubview(row([button("Start / Resume", #selector(startOrResume)), button("Pause", #selector(pause)), button("Stop", #selector(stop))]))

        content.addArrangedSubview(sectionTitle("Run interval"))
        content.addArrangedSubview(row([
            label("Minimum seconds"), fixedWidth(minimumIntervalField, 65),
            label("Maximum seconds"), fixedWidth(maximumIntervalField, 65), randomIntervalButton
        ]))
        content.addArrangedSubview(row([keepAwakeButton, pauseOnBatteryButton, launchAtLoginButton]))
        content.addArrangedSubview(row([autoPauseButton, autoResumeButton, label("Resume after idle (seconds)"), fixedWidth(autoResumeSecondsField, 65)]))

        content.addArrangedSubview(sectionTitle("Actions"))
        actionKindPopup.addItems(withTitles: ActionKind.allCases.map(\.title))
        content.addArrangedSubview(row([actionKindPopup, button("Add action", #selector(addAction))]))
        content.addArrangedSubview(tableScrollView(for: actionTable, height: 95))
        actionTriggerPopup.addItems(withTitles: ActionTrigger.allCases.map(\.title))
        actionEnabledButton.state = .on
        content.addArrangedSubview(row([label("Name"), fixedWidth(actionNameField, 120), label("Trigger"), actionTriggerPopup, actionEnabledButton]))
        content.addArrangedSubview(row([actionRepeatButton, label("Repeat limit (0 = unlimited)"), fixedWidth(repeatLimitField, 60), waitForExitButton]))
        content.addArrangedSubview(row([label("Parameter"), actionParameterField]))
        content.addArrangedSubview(row([label("Arguments"), actionArgumentsField, button("Save action", #selector(saveAction)), button("Remove", #selector(removeAction))]))
        actionHelpLabel.textColor = .secondaryLabelColor
        actionHelpLabel.font = .systemFont(ofSize: 11)
        content.addArrangedSubview(actionHelpLabel)

        content.addArrangedSubview(sectionTitle("Schedules (local time)"))
        scheduleActionPopup.addItems(withTitles: ["Start", "Stop"])
        scheduleWeekdaysField.placeholderString = "Sun,Mon,Tue,Wed,Thu,Fri,Sat"
        content.addArrangedSubview(row([
            label("Time"), fixedWidth(scheduleTimeField, 70), label("Days"), fixedWidth(scheduleWeekdaysField, 220),
            scheduleActionPopup, button("Add schedule", #selector(addSchedule))
        ]))
        content.addArrangedSubview(tableScrollView(for: scheduleTable, height: 75))
        content.addArrangedSubview(sectionTitle("Blackout windows"))
        content.addArrangedSubview(row([
            label("Start"), fixedWidth(blackoutTimeField, 70), label("Duration (min)"), fixedWidth(blackoutDurationField, 65),
            label("Days"), fixedWidth(blackoutWeekdaysField, 220), button("Add blackout", #selector(addBlackout))
        ]))
        content.addArrangedSubview(tableScrollView(for: blackoutTable, height: 55))
        content.addArrangedSubview(row([
            button("Remove selected schedule", #selector(removeSchedule)),
            button("Remove selected blackout", #selector(removeBlackout)),
            button("Save preferences", #selector(saveSettings))
        ]))

        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 3
        content.addArrangedSubview(errorLabel)
        let pathLabel = NSTextField(labelWithString: "Settings: \(SettingsStore.settingsURL.path)")
        pathLabel.font = .systemFont(ofSize: 10)
        pathLabel.textColor = .tertiaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        content.addArrangedSubview(pathLabel)

        let frame = NSRect(x: 0, y: 0, width: 820, height: 850)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Move Mouse"
        window.minSize = NSSize(width: 750, height: 620)
        window.center()
        window.contentView = content
        window.delegate = self

        for table in [actionTable, scheduleTable, blackoutTable] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
            column.title = ""
            column.width = 760
            table.addTableColumn(column)
            table.headerView = nil
            table.rowHeight = 22
            table.delegate = self
            table.dataSource = self
        }
        actionTable.target = self
        actionTable.action = #selector(actionRowSelected)
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "MM"
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Move Mouse", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(withTitle: "Start / Pause", action: #selector(toggleRunState), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Move Mouse", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    private func populateControls() {
        minimumIntervalField.stringValue = String(settings.minimumInterval)
        maximumIntervalField.stringValue = String(settings.maximumInterval)
        randomIntervalButton.state = settings.randomInterval ? .on : .off
        keepAwakeButton.state = settings.keepAwake ? .on : .off
        pauseOnBatteryButton.state = settings.pauseOnBattery ? .on : .off
        autoPauseButton.state = settings.autoPause ? .on : .off
        autoResumeButton.state = settings.autoResume ? .on : .off
        autoResumeSecondsField.stringValue = String(settings.autoResumeSeconds)
        launchAtLoginButton.state = SMAppService.mainApp.status == .enabled ? .on : .off
        reloadTables()
    }

    private func reloadTables() {
        actionTable.reloadData()
        scheduleTable.reloadData()
        blackoutTable.reloadData()
        if let selectedActionIndex, settings.actions.indices.contains(selectedActionIndex) {
            actionTable.selectRowIndexes(IndexSet(integer: selectedActionIndex), byExtendingSelection: false)
            showAction(at: selectedActionIndex)
        }
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 8
        return stack
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 14, weight: .semibold)
        return field
    }

    private func label(_ text: String) -> NSTextField { NSTextField(labelWithString: text) }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    private func fixedWidth(_ view: NSView, _ width: CGFloat) -> NSView {
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        return view
    }

    private func tableScrollView(for table: NSTableView, height: CGFloat) -> NSScrollView {
        let scroll = NSScrollView()
        table.frame = NSRect(x: 0, y: 0, width: 760, height: height)
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 780).isActive = true
        return scroll
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === actionTable { return settings.actions.count }
        if tableView === scheduleTable { return settings.schedules.count }
        return settings.blackouts.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let summary: String
        if tableView === actionTable { summary = settings.actions[row].summary }
        else if tableView === scheduleTable { summary = settings.schedules[row].summary }
        else { summary = settings.blackouts[row].summary }
        let text = NSTextField(labelWithString: summary)
        text.lineBreakMode = .byTruncatingTail
        return text
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView, table === actionTable else { return }
        let row = actionTable.selectedRow
        guard settings.actions.indices.contains(row) else { selectedActionIndex = nil; return }
        showAction(at: row)
    }

    private func showAction(at index: Int) {
        guard settings.actions.indices.contains(index) else { return }
        selectedActionIndex = index
        let action = settings.actions[index]
        actionKindPopup.selectItem(withTitle: action.kind.title)
        actionNameField.stringValue = action.name
        actionParameterField.stringValue = action.parameter
        actionArgumentsField.stringValue = action.arguments
        actionTriggerPopup.selectItem(withTitle: action.trigger.title)
        actionEnabledButton.state = action.enabled ? .on : .off
        actionRepeatButton.state = action.repeatAction ? .on : .off
        repeatLimitField.stringValue = String(action.repeatLimit)
        waitForExitButton.state = action.waitForExit ? .on : .off
        actionHelpLabel.stringValue = helpText(for: action.kind)
    }

    @objc private func actionRowSelected() {
        if settings.actions.indices.contains(actionTable.selectedRow) { showAction(at: actionTable.selectedRow) }
    }

    @objc private func addAction() {
        let kind = ActionKind.allCases.first { $0.title == actionKindPopup.titleOfSelectedItem } ?? .moveMouse
        let parameter: String
        switch kind {
        case .moveMouse: parameter = "square, 10"
        case .positionMouse: parameter = "400, 300"
        case .clickMouse: parameter = "left"
        case .scrollMouse: parameter = "down, 100"
        case .keystroke: parameter = "49"
        case .runCommand, .runScript, .activateApplication: parameter = ""
        case .sleep: parameter = "1"
        }
        settings.actions.append(AutomationAction(kind: kind, parameter: parameter))
        selectedActionIndex = settings.actions.count - 1
        reloadTables()
    }

    @objc private func saveAction() {
        guard let index = selectedActionIndex, settings.actions.indices.contains(index) else {
            showError("Select an action before saving it.")
            return
        }
        guard let kind = ActionKind.allCases.first(where: { $0.title == actionKindPopup.titleOfSelectedItem }),
              let trigger = ActionTrigger.allCases.first(where: { $0.title == actionTriggerPopup.titleOfSelectedItem }),
              let repeatLimit = Int(repeatLimitField.stringValue), repeatLimit >= 0 else {
            showError("Choose a valid action type and trigger, and use a non-negative whole-number repeat limit.")
            return
        }
        var action = settings.actions[index]
        action.kind = kind
        action.name = actionNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        action.parameter = actionParameterField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        action.arguments = actionArgumentsField.stringValue
        action.trigger = trigger
        action.enabled = actionEnabledButton.state == .on
        action.repeatAction = actionRepeatButton.state == .on
        action.repeatLimit = repeatLimit
        action.waitForExit = waitForExitButton.state == .on
        settings.actions[index] = action
        engine.configure(settings)
        reloadTables()
        clearError()
    }

    @objc private func removeAction() {
        guard let index = selectedActionIndex, settings.actions.indices.contains(index) else { return }
        settings.actions.remove(at: index)
        selectedActionIndex = settings.actions.isEmpty ? nil : min(index, settings.actions.count - 1)
        reloadTables()
    }

    @objc private func addSchedule() {
        let time = scheduleTimeField.stringValue.trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        guard formatter.date(from: time) != nil else { showError("Schedule time must use 24-hour HH:mm format."); return }
        let days = parseWeekdays(scheduleWeekdaysField.stringValue)
        guard !days.isEmpty else { showError("Enter at least one weekday: Sun, Mon, Tue, Wed, Thu, Fri, Sat."); return }
        let action = scheduleActionPopup.indexOfSelectedItem == 1 ? ScheduleAction.stop : .start
        settings.schedules.append(ScheduledRule(time: time, weekdays: days, action: action))
        scheduleTable.reloadData()
        clearError()
    }

    @objc private func removeSchedule() {
        let index = scheduleTable.selectedRow
        guard settings.schedules.indices.contains(index) else { return }
        settings.schedules.remove(at: index)
        scheduleTable.reloadData()
    }

    @objc private func addBlackout() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        let time = blackoutTimeField.stringValue.trimmingCharacters(in: .whitespaces)
        guard formatter.date(from: time) != nil,
              let duration = Int(blackoutDurationField.stringValue), (1...1440).contains(duration) else {
            showError("Blackouts need a 24-hour HH:mm start time and a duration from 1 to 1440 minutes.")
            return
        }
        let days = parseWeekdays(blackoutWeekdaysField.stringValue)
        guard !days.isEmpty else { showError("Enter at least one weekday: Sun, Mon, Tue, Wed, Thu, Fri, Sat."); return }
        settings.blackouts.append(BlackoutRule(time: time, durationMinutes: duration, weekdays: days))
        blackoutTable.reloadData()
        clearError()
    }

    @objc private func removeBlackout() {
        let index = blackoutTable.selectedRow
        guard settings.blackouts.indices.contains(index) else { return }
        settings.blackouts.remove(at: index)
        blackoutTable.reloadData()
    }

    private func parseWeekdays(_ value: String) -> Set<Int> {
        let dayMap = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
        let tokens = value.lowercased().split { !$0.isLetter }
        return Set(tokens.compactMap { dayMap[String($0.prefix(3))] })
    }

    @objc private func saveSettings() {
        guard let minimum = Int(minimumIntervalField.stringValue), minimum >= 1,
              let maximum = Int(maximumIntervalField.stringValue), maximum >= minimum,
              let resumeAfter = Int(autoResumeSecondsField.stringValue), resumeAfter >= 1 else {
            showError("Intervals must be positive whole seconds, maximum must be at least minimum, and auto-resume must be at least one second.")
            return
        }
        settings.minimumInterval = minimum
        settings.maximumInterval = maximum
        settings.randomInterval = randomIntervalButton.state == .on
        settings.keepAwake = keepAwakeButton.state == .on
        settings.pauseOnBattery = pauseOnBatteryButton.state == .on
        settings.autoPause = autoPauseButton.state == .on
        settings.autoResume = autoResumeButton.state == .on
        settings.autoResumeSeconds = resumeAfter
        let wantsLogin = launchAtLoginButton.state == .on
        do {
            if wantsLogin && SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !wantsLogin && SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            settings.launchAtLogin = wantsLogin
        } catch {
            showError("Could not update the macOS login item: \(error.localizedDescription)")
            return
        }
        do {
            try SettingsStore.save(settings)
            engine.configure(settings)
            clearError()
            statusLabel.stringValue = "\(engine.state.rawValue) — preferences saved"
        } catch {
            showError("Could not save settings: \(error.localizedDescription)")
        }
    }

    @objc private func startOrResume() {
        guard engine.state != .running else { return }
        engine.configure(settings)
        engine.start()
    }

    @objc private func toggleRunState() {
        if engine.state == .running { engine.pause() }
        else { engine.configure(settings); engine.start() }
    }

    @objc private func pause() { engine.pause() }
    @objc private func stop() { engine.stop() }

    @objc private func requestPermission() {
        _ = InputController.requestAccessibilityAccess()
        updatePermissionStatus()
        if !InputController.hasAccessibilityAccess,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func updatePermissionStatus() {
        permissionLabel.stringValue = InputController.hasAccessibilityAccess
            ? "Accessibility access is enabled."
            : "Mouse and keyboard actions require Accessibility access; system-only keep-awake and schedules work without it."
    }

    private func updateState(_ state: AutomationEngine.State) {
        statusLabel.stringValue = state.rawValue
        statusItem.button?.title = state == .running ? "● MM" : state == .paused ? "Ⅱ MM" : "MM"
        updatePermissionStatus()
    }

    private func helpText(for kind: ActionKind) -> String {
        switch kind {
        case .moveMouse: return "Direction, distance (1–500); directions include square, none, random, compass points, and back-and-forth paths."
        case .positionMouse: return "Screen coordinates as x, y (for example: 400, 300)."
        case .clickMouse: return "Button and optional hold duration in seconds (for example: left, 0.5)."
        case .scrollMouse: return "Direction and distance (for example: down, 100); direction can be up, down, left, right, or random."
        case .keystroke: return "Comma-separated macOS virtual key codes (for example: 49 for Space). Windows key codes are not interchangeable."
        case .runCommand: return "Executable path; Arguments uses shell-style quotes and escapes."
        case .runScript: return "Shell script path; runs through /bin/zsh without opening Terminal."
        case .activateApplication: return "A running application's bundle ID, installed bundle ID, or .app path."
        case .sleep: return "Delay in seconds before the next action."
        }
    }

    private func showError(_ message: String) {
        errorLabel.stringValue = message
        NSLog("Move Mouse: %@", message)
    }

    private func clearError() { errorLabel.stringValue = "" }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Move Mouse settings issue"
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        engine.stop()
        NSApp.terminate(nil)
    }
}

@main
struct MoveMouseMacApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}
