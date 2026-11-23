import Foundation

@main
struct ModelTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 14, minute: 26)) else {
            fatalError("Could not construct test date")
        }
        let monday = ScheduledRule(time: "14:26", weekdays: [2], action: .start)
        let wrongTime = ScheduledRule(time: "14:27", weekdays: [2], action: .start)
        let wrongDay = ScheduledRule(time: "14:26", weekdays: [3], action: .start)

        precondition(monday.matches(date, calendar: calendar), "Schedule should match its configured weekday and minute")
        precondition(!wrongTime.matches(date, calendar: calendar), "Schedule should reject a different minute")
        precondition(!wrongDay.matches(date, calendar: calendar), "Schedule should reject a different weekday")
        precondition(!ScheduledRule(time: "25:99", weekdays: [2]).matches(date, calendar: calendar), "Malformed schedule time should not match")

        let overnight = BlackoutRule(time: "22:00", durationMinutes: 240, weekdays: [3])
        let tuesdayLate = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 23, minute: 0))!
        let wednesdayEarly = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 1, minute: 0))!
        let wednesdayAfter = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 2, minute: 0))!
        precondition(overnight.isActive(tuesdayLate, calendar: calendar), "Blackout should be active on its start day")
        precondition(overnight.isActive(wednesdayEarly, calendar: calendar), "Overnight blackout should continue into the next day")
        precondition(!overnight.isActive(wednesdayAfter, calendar: calendar), "Blackout should end after its configured duration")
        let migratedSettings = try! JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        precondition(migratedSettings.minimumInterval == 30 && migratedSettings.actions.count == 1, "Settings with newly added optional fields should load with defaults")
        print("Passed 8 scheduling and settings checks")
    }
}
