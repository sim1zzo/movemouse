import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case actions
    case schedules
    case blackouts
    case permissions

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .general: return "General"
        case .actions: return "Actions"
        case .schedules: return "Schedules"
        case .blackouts: return "Blackouts"
        case .permissions: return "Permissions"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .actions: return "cursorarrow.motionlines"
        case .schedules: return "calendar"
        case .blackouts: return "moon"
        case .permissions: return "hand.raised"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: sectionSelection) { section in
                Label(section.title, systemImage: section.symbol)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            detail
                .navigationTitle(model.selectedSection.title)
                .safeAreaInset(edge: .bottom) {
                    if let error = model.errorMessage {
                        NoticeBox(symbol: "xmark.octagon.fill", tint: .red) {
                            Text(error).fixedSize(horizontal: false, vertical: true)
                            Button("Dismiss") { model.errorMessage = nil }.controlSize(.small)
                        }
                        .padding(12)
                    }
                }
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    private var sectionSelection: Binding<SettingsSection?> {
        Binding(get: { model.selectedSection }, set: { if let value = $0 { model.selectedSection = value } })
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedSection {
        case .general: GeneralSettingsView()
        case .actions: ActionsSettingsView()
        case .schedules: SchedulesSettingsView()
        case .blackouts: BlackoutsSettingsView()
        case .permissions: PermissionsSettingsView()
        }
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Random interval", isOn: $model.settings.randomInterval)
                NumberField(title: model.settings.randomInterval ? "Minimum interval" : "Interval",
                            value: minimumInterval, range: 1...86_400, unit: "s")
                if model.settings.randomInterval {
                    NumberField(title: "Maximum interval", value: maximumInterval, range: 1...86_400, unit: "s")
                }
            } header: {
                Text("Run interval")
            } footer: {
                Text("How often the interval actions run while Move Mouse is active.")
                    .foregroundStyle(.secondary)
            }

            Section("Behaviour") {
                Toggle("Keep Mac awake while running", isOn: $model.settings.keepAwake)
                Toggle("Pause on battery", isOn: $model.settings.pauseOnBattery)
                Toggle("Pause while I use the Mac", isOn: $model.settings.autoPause)
                Toggle("Resume automatically when I stop", isOn: $model.settings.autoResume)
                if model.settings.autoResume {
                    NumberField(title: "Resume after inactivity", value: $model.settings.autoResumeSeconds, range: 1...86_400, unit: "s")
                }
            }

            Section("System") {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                LabeledContent("Settings file") {
                    Button("Show in Finder") { model.revealSettingsFile() }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Raising the minimum above the maximum drags the maximum along, so the pair is always valid.
    private var minimumInterval: Binding<Int> {
        Binding(get: { model.settings.minimumInterval }, set: { value in
            model.settings.minimumInterval = value
            if model.settings.maximumInterval < value { model.settings.maximumInterval = value }
        })
    }

    private var maximumInterval: Binding<Int> {
        Binding(get: { model.settings.maximumInterval }, set: { value in
            model.settings.maximumInterval = value
            if model.settings.minimumInterval > value { model.settings.minimumInterval = value }
        })
    }
}

/// Numeric field + stepper, clamped to `range`.
struct NumberField: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    var unit: String? = nil

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField("", value: clamped, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Stepper("", value: clamped, in: range)
                    .labelsHidden()
                if let unit {
                    Text(verbatim: unit).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var clamped: Binding<Int> {
        Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) })
    }
}

// MARK: - Actions

private struct ActionsSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(model.settings.actions) { action in
                        ActionRow(action: action)
                            .tag(action.id)
                    }
                    .onMove { model.settings.actions.move(fromOffsets: $0, toOffset: $1) }
                }
                Divider()
                HStack(spacing: 2) {
                    Menu {
                        ForEach(ActionKind.allCases) { kind in
                            Button {
                                add(kind)
                            } label: {
                                Label(kind.localizedTitle, systemImage: kind.symbol)
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 28)
                    .help("Add action")

                    Button {
                        removeSelected()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 28)
                    .disabled(selection == nil)
                    .help("Remove action")

                    Spacer()
                }
                .padding(6)
            }
            .frame(width: 260)

            Divider()

            if let id = selection, model.settings.actions.contains(where: { $0.id == id }) {
                ActionDetailView(action: model.actionBinding(id))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "cursorarrow.motionlines")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("Select an action, or add one with +.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selection == nil { selection = model.settings.actions.first?.id }
        }
    }

    private func add(_ kind: ActionKind) {
        let action = AutomationAction(kind: kind, parameter: kind.defaultParameter)
        model.settings.actions.append(action)
        selection = action.id
    }

    private func removeSelected() {
        guard let id = selection, let index = model.settings.actions.firstIndex(where: { $0.id == id }) else { return }
        model.settings.actions.remove(at: index)
        selection = model.settings.actions.isEmpty ? nil : model.settings.actions[min(index, model.settings.actions.count - 1)].id
    }
}

private struct ActionRow: View {
    let action: AutomationAction

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.kind.symbol)
                .frame(width: 20)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.name.isEmpty ? action.kind.localizedTitle : action.name)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .opacity(action.enabled ? 1 : 0.45)
    }

    private var detail: String {
        [action.parameter, action.trigger.localizedTitle].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private struct ActionDetailView: View {
    @Binding var action: AutomationAction

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: $action.enabled)
                Picker("Type", selection: kind) {
                    ForEach(ActionKind.allCases) { kind in
                        Text(kind.localizedTitle).tag(kind)
                    }
                }
                TextField("Name", text: $action.name, prompt: Text(action.kind.localizedTitle))
                Picker("When", selection: $action.trigger) {
                    ForEach(ActionTrigger.allCases) { trigger in
                        Text(trigger.localizedTitle).tag(trigger)
                    }
                }
            }

            Section {
                TextField("Parameter", text: $action.parameter)
                if action.kind == .runCommand {
                    TextField("Arguments", text: $action.arguments)
                }
                if action.kind == .runCommand || action.kind == .runScript {
                    Toggle("Wait for it to finish", isOn: $action.waitForExit)
                }
            } footer: {
                Text(action.kind.localizedHelp)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if action.trigger == .interval {
                Section {
                    Toggle("Repeat on every interval", isOn: $action.repeatAction)
                    if action.repeatAction {
                        NumberField(title: "Maximum repetitions", value: $action.repeatLimit, range: 0...100_000)
                    }
                } footer: {
                    if action.repeatAction {
                        Text("0 means unlimited.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Changing the type resets the parameter to a valid example for the new type.
    private var kind: Binding<ActionKind> {
        Binding(get: { action.kind }, set: { newKind in
            guard newKind != action.kind else { return }
            action.kind = newKind
            action.parameter = newKind.defaultParameter
        })
    }
}

// MARK: - Schedules

private struct SchedulesSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                if model.settings.schedules.isEmpty {
                    Text("No schedules yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.settings.schedules) { rule in
                    ScheduleRow(rule: model.scheduleBinding(rule.id)) {
                        model.settings.schedules.removeAll { $0.id == rule.id }
                    }
                }
            } header: {
                HStack {
                    Text("Start or stop automatically")
                    Spacer()
                    Button {
                        model.settings.schedules.append(ScheduledRule(time: "09:00", weekdays: Set(2...6), action: .start))
                    } label: {
                        Label("Add schedule", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            } footer: {
                Text("Times use the Mac's local time zone.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ScheduleRow: View {
    @Binding var rule: ScheduledRule
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $rule.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            Picker("", selection: $rule.action) {
                Text("Start").tag(ScheduleAction.start)
                Text("Stop").tag(ScheduleAction.stop)
            }
            .labelsHidden()
            .frame(width: 100)
            DatePicker("", selection: timeBinding($rule.time), displayedComponents: .hourAndMinute)
                .labelsHidden()
            WeekdayPicker(selection: $rule.weekdays)
            Spacer()
            DeleteButton(action: onDelete)
        }
        .opacity(rule.enabled ? 1 : 0.5)
    }
}

// MARK: - Blackouts

private struct BlackoutsSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                if model.settings.blackouts.isEmpty {
                    Text("No blackout windows yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.settings.blackouts) { rule in
                    BlackoutRow(rule: model.blackoutBinding(rule.id)) {
                        model.settings.blackouts.removeAll { $0.id == rule.id }
                    }
                }
            } header: {
                HStack {
                    Text("Periods with no activity")
                    Spacer()
                    Button {
                        model.settings.blackouts.append(BlackoutRule(time: "12:30", durationMinutes: 60, weekdays: Set(2...6)))
                    } label: {
                        Label("Add blackout", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            } footer: {
                Text("While a blackout is active, Move Mouse pauses and resumes afterwards.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct BlackoutRow: View {
    @Binding var rule: BlackoutRule
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $rule.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            DatePicker("", selection: timeBinding($rule.time), displayedComponents: .hourAndMinute)
                .labelsHidden()
            Stepper(value: $rule.durationMinutes, in: 5...1440, step: 5) {
                Text("\(rule.durationMinutes) min")
                    .monospacedDigit()
                    .frame(minWidth: 64, alignment: .trailing)
            }
            WeekdayPicker(selection: $rule.weekdays)
            Spacer()
            DeleteButton(action: onDelete)
        }
        .opacity(rule.enabled ? 1 : 0.5)
    }
}

// MARK: - Permissions

private struct PermissionsSettingsView: View {
    @EnvironmentObject private var model: AppModel
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: model.hasAccessibilityAccess ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(model.hasAccessibilityAccess ? .green : .orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Accessibility")
                            .font(.headline)
                        if model.hasAccessibilityAccess {
                            Text("Access granted. Move Mouse can move the pointer, click, scroll and press keys.")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Without this permission Move Mouse can still keep the Mac awake and follow schedules, but it cannot move the mouse or press keys.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Button("Grant access…") { model.requestAccessibilityAccess() }
                                    .buttonStyle(.borderedProminent)
                                Button("Open System Settings") { model.openAccessibilitySettings() }
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("If Move Mouse is already in the list but access still shows as missing (common after installing a new build), remove it with the − button and add it again.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onReceive(refreshTimer) { _ in model.refreshPermission() }
    }
}

// MARK: - Shared controls

/// Seven round day buttons, ordered by the user's first weekday. Values use Calendar weekdays (1 = Sunday).
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 4) {
            ForEach(orderedDays, id: \.self) { day in
                Button {
                    toggle(day)
                } label: {
                    Text(calendar.veryShortStandaloneWeekdaySymbols[day - 1])
                        .font(.caption.weight(.semibold))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle().fill(selection.contains(day) ? Color.accentColor : Color.secondary.opacity(0.15))
                        )
                        .foregroundColor(selection.contains(day) ? .white : .primary)
                }
                .buttonStyle(.plain)
                .help(calendar.standaloneWeekdaySymbols[day - 1])
            }
        }
    }

    private var orderedDays: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// At least one day must stay selected, otherwise the rule could never fire.
    private func toggle(_ day: Int) {
        if selection.contains(day) {
            if selection.count > 1 { selection.remove(day) }
        } else {
            selection.insert(day)
        }
    }
}

private struct DeleteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .help("Delete")
    }
}

/// Bridges the "HH:mm" strings stored in settings to a Date for DatePicker.
private func timeBinding(_ time: Binding<String>) -> Binding<Date> {
    Binding(
        get: {
            let parts = time.wrappedValue.split(separator: ":").compactMap { Int($0) }
            let hour = parts.count == 2 ? parts[0] : 9
            let minute = parts.count == 2 ? parts[1] : 0
            return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        },
        set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            time.wrappedValue = String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
        }
    )
}
