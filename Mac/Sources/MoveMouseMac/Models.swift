import Foundation

enum ActionKind: String, CaseIterable, Codable, Identifiable {
    case moveMouse
    case positionMouse
    case clickMouse
    case scrollMouse
    case keystroke
    case runCommand
    case runScript
    case activateApplication
    case sleep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moveMouse: return "Move mouse"
        case .positionMouse: return "Position mouse"
        case .clickMouse: return "Click mouse"
        case .scrollMouse: return "Scroll mouse"
        case .keystroke: return "Keystroke"
        case .runCommand: return "Run command"
        case .runScript: return "Run shell script"
        case .activateApplication: return "Activate application"
        case .sleep: return "Wait"
        }
    }
}

enum ActionTrigger: String, CaseIterable, Codable, Identifiable {
    case start
    case interval
    case stop

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct AutomationAction: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: ActionKind = .moveMouse
    var name = ""
    var parameter = "square, 10"
    var arguments = ""
    var trigger: ActionTrigger = .interval
    var enabled = true
    var repeatAction = true
    var repeatLimit = 0
    var waitForExit = false

    var summary: String {
        let value = [parameter, arguments].filter { !$0.isEmpty }.joined(separator: " ")
        return "\(name.isEmpty ? kind.title : name) — \(value) [\(trigger.title)]"
    }
}

enum ScheduleAction: String, CaseIterable, Codable, Identifiable {
    case start
    case stop

    var id: String { rawValue }
}

struct ScheduledRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var time = "09:00"
    var weekdays = Set(1...7)
    var action: ScheduleAction = .start
    var enabled = true

    var summary: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        let days = weekdays.sorted().map { day in
            formatter.shortWeekdaySymbols[(day - 1) % 7]
        }.joined(separator: ",")
        return "\(action.rawValue.capitalized) at \(time) (\(days))"
    }

    func matches(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled,
              let parts = time.split(separator: ":").compactMap({ Int($0) }).asPair,
              (0...23).contains(parts.0),
              (0...59).contains(parts.1) else { return false }
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        return weekdays.contains(components.weekday ?? 0)
            && components.hour == parts.0
            && components.minute == parts.1
    }
}

struct BlackoutRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var time = "22:00"
    var durationMinutes = 60
    var weekdays = Set(1...7)
    var enabled = true

    var summary: String {
        "No activity from \(time) for \(durationMinutes) min (\(weekdays.sorted().map { Calendar.current.shortWeekdaySymbols[($0 - 1) % 7] }.joined(separator: ",")))"
    }

    func isActive(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled, (1...1440).contains(durationMinutes),
              let parts = time.split(separator: ":").compactMap({ Int($0) }).asPair,
              (0...23).contains(parts.0), (0...59).contains(parts.1) else { return false }
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = components.weekday, let hour = components.hour, let minute = components.minute else { return false }
        let currentMinute = hour * 60 + minute
        let startMinute = parts.0 * 60 + parts.1
        let endMinute = startMinute + durationMinutes
        if endMinute <= 1440 {
            return weekdays.contains(weekday) && currentMinute >= startMinute && currentMinute < endMinute
        }
        let previousDay = weekday == 1 ? 7 : weekday - 1
        return (weekdays.contains(weekday) && currentMinute >= startMinute)
            || (weekdays.contains(previousDay) && currentMinute < endMinute - 1440)
    }
}

private extension Collection where Element == Int {
    var asPair: (Int, Int)? {
        guard count == 2 else { return nil }
        let values = Array(self)
        return (values[0], values[1])
    }
}

struct AppSettings: Codable {
    var minimumInterval = 30
    var maximumInterval = 60
    var randomInterval = false
    var keepAwake = true
    var pauseOnBattery = false
    var autoPause = false
    var autoResume = false
    var autoResumeSeconds = 30
    var launchAtLogin = false
    var actions = [AutomationAction()]
    var schedules = [ScheduledRule]()
    var blackouts = [BlackoutRule]()

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        minimumInterval = try values.decodeIfPresent(Int.self, forKey: .minimumInterval) ?? 30
        maximumInterval = try values.decodeIfPresent(Int.self, forKey: .maximumInterval) ?? 60
        randomInterval = try values.decodeIfPresent(Bool.self, forKey: .randomInterval) ?? false
        keepAwake = try values.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? true
        pauseOnBattery = try values.decodeIfPresent(Bool.self, forKey: .pauseOnBattery) ?? false
        autoPause = try values.decodeIfPresent(Bool.self, forKey: .autoPause) ?? false
        autoResume = try values.decodeIfPresent(Bool.self, forKey: .autoResume) ?? false
        autoResumeSeconds = try values.decodeIfPresent(Int.self, forKey: .autoResumeSeconds) ?? 30
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        actions = try values.decodeIfPresent([AutomationAction].self, forKey: .actions) ?? [AutomationAction()]
        schedules = try values.decodeIfPresent([ScheduledRule].self, forKey: .schedules) ?? []
        blackouts = try values.decodeIfPresent([BlackoutRule].self, forKey: .blackouts) ?? []
    }
}

enum SettingsStore {
    static var settingsURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MoveMouse", isDirectory: true).appendingPathComponent("settings.json")
    }

    static func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return AppSettings() }
        return try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: settingsURL))
    }

    static func save(_ settings: AppSettings) throws {
        let directory = settingsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: settingsURL, options: .atomic)
    }
}
