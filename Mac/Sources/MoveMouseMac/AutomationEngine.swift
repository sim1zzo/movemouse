import ApplicationServices
import Foundation
import IOKit.pwr_mgt
import IOKit.ps

@MainActor
final class AutomationEngine {
    enum State: String {
        case stopped = "Stopped"
        case running = "Running"
        case paused = "Paused"
    }

    private(set) var state: State = .stopped
    private var settings = AppSettings()
    private var intervalTimer: Timer?
    private var monitorTimer: Timer?
    private var powerAssertion: IOPMAssertionID = 0
    private var automaticPause = false
    private var pauseDueToBattery = false
    private var pauseDueToBlackout = false
    private var generation = 0
    private var lastFiredMinute: [UUID: String] = [:]
    private var firstIntervalCycle = true
    private var intervalExecutionCounts: [UUID: Int] = [:]
    private var ignoreActivityUntil = Date.distantPast

    var onStateChanged: ((State) -> Void)?
    var onError: ((String) -> Void)?
    /// Called with the date of the next interval run, or nil when nothing is scheduled.
    var onNextRunChanged: ((Date?) -> Void)?

    func configure(_ settings: AppSettings) {
        self.settings = settings
        if state == .running {
            if settings.keepAwake { beginPowerAssertion() } else { endPowerAssertion() }
        }
    }

    func start() {
        guard state != .running else { return }
        if settings.blackouts.contains(where: { $0.isActive(Date()) }) {
            pauseDueToBlackout = true
            setState(.paused)
            startMonitor()
            return
        }
        if settings.pauseOnBattery && runningOnBattery {
            pauseDueToBattery = true
            setState(.paused)
            startMonitor()
            return
        }

        pauseDueToBattery = false
        pauseDueToBlackout = false
        automaticPause = false
        generation += 1
        firstIntervalCycle = true
        intervalExecutionCounts.removeAll()
        setState(.running)
        if settings.keepAwake { beginPowerAssertion() }
        startMonitor()
        perform(trigger: .start, generation: generation) { [weak self] in self?.scheduleNextInterval() }
    }

    func pause() {
        pause(automatically: false)
    }

    private func pause(automatically: Bool) {
        guard state == .running else { return }
        automaticPause = automatically
        intervalTimer?.invalidate()
        intervalTimer = nil
        endPowerAssertion()
        generation += 1
        setState(.paused)
        perform(trigger: .stop, generation: generation, allowStopped: true)
    }

    func stop() {
        guard state != .stopped else { return }
        let wasRunning = state == .running
        intervalTimer?.invalidate()
        monitorTimer?.invalidate()
        intervalTimer = nil
        monitorTimer = nil
        endPowerAssertion()
        generation += 1
        automaticPause = false
        pauseDueToBattery = false
        pauseDueToBlackout = false
        setState(.stopped)
        if wasRunning { perform(trigger: .stop, generation: generation, allowStopped: true) }
    }

    func toggle() {
        switch state {
        case .running: pause()
        case .paused: start()
        case .stopped: start()
        }
    }

    private func setState(_ newState: State) {
        state = newState
        if newState != .running { onNextRunChanged?(nil) }
        onStateChanged?(newState)
    }

    private func scheduleNextInterval() {
        intervalTimer?.invalidate()
        let lower = max(1, settings.minimumInterval)
        let upper = max(lower, settings.maximumInterval)
        let seconds = settings.randomInterval && upper > lower ? Double(Int.random(in: lower..<upper)) : Double(lower)
        onNextRunChanged?(Date().addingTimeInterval(seconds))
        intervalTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .running else { return }
                if self.settings.pauseOnBattery && self.runningOnBattery {
                    self.pauseDueToBattery = true
                    self.pause()
                    return
                }
                let actions = self.settings.actions.filter { action in
                    guard action.enabled, action.trigger == .interval else { return false }
                    return self.firstIntervalCycle || (action.repeatAction && (action.repeatLimit == 0 || self.intervalExecutionCounts[action.id, default: 0] < action.repeatLimit))
                }
                self.firstIntervalCycle = false
                guard !actions.isEmpty else {
                    self.onError?("Automatically stopped: no interval action is enabled for another run.")
                    self.stop()
                    return
                }
                self.perform(trigger: .interval, generation: self.generation, actions: actions) { [weak self] in
                    guard let self, self.state == .running else { return }
                    let moreActionsCanRepeat = self.settings.actions.contains { action in
                        action.enabled && action.trigger == .interval && action.repeatAction
                            && (action.repeatLimit == 0 || self.intervalExecutionCounts[action.id, default: 0] < action.repeatLimit)
                    }
                    if moreActionsCanRepeat { self.scheduleNextInterval() } else { self.stop() }
                }
            }
        }
    }

    private func startMonitor() {
        monitorTimer?.invalidate()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.checkSchedules()
                self.checkBlackouts()
                self.checkIdleState()
                if self.state == .running && self.settings.pauseOnBattery && self.runningOnBattery {
                    self.pauseDueToBattery = true
                    self.pause()
                }
                if self.pauseDueToBattery && !self.runningOnBattery {
                    self.pauseDueToBattery = false
                    self.start()
                }
            }
        }
    }

    private func checkBlackouts() {
        let active = settings.blackouts.contains { $0.isActive(Date()) }
        if active, state == .running {
            pauseDueToBlackout = true
            intervalTimer?.invalidate()
            intervalTimer = nil
            endPowerAssertion()
            setState(.paused)
        } else if !active, pauseDueToBlackout {
            pauseDueToBlackout = false
            start()
        }
    }

    private func checkIdleState() {
        guard Date() >= ignoreActivityUntil else { return }
        let idleSeconds = min(
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved),
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        )
        if state == .running, settings.autoPause, idleSeconds < 1 {
            if settings.autoResume {
                pause(automatically: true)
            } else {
                stop()
            }
        } else if state == .paused, automaticPause, settings.autoResume,
                  idleSeconds >= Double(max(1, settings.autoResumeSeconds)) {
            automaticPause = false
            start()
        }
    }

    private func checkSchedules() {
        let now = Date()
        let key = ISO8601DateFormatter().string(from: Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now)
        for rule in settings.schedules where rule.matches(now) {
            guard lastFiredMinute[rule.id] != key else { continue }
            lastFiredMinute[rule.id] = key
            if rule.action == .start { start() } else { stop() }
        }
    }

    private func perform(trigger: ActionTrigger, generation: Int, allowStopped: Bool = false, actions: [AutomationAction]? = nil, completion: (() -> Void)? = nil) {
        let selectedActions = actions ?? settings.actions.filter { $0.enabled && $0.trigger == trigger }
        execute(selectedActions, at: 0, generation: generation, allowStopped: allowStopped, completion: completion)
    }

    private func execute(_ actions: [AutomationAction], at index: Int, generation: Int, allowStopped: Bool, completion: (() -> Void)?) {
        guard self.generation == generation else { return }
        guard allowStopped || state == .running else { completion?(); return }
        guard index < actions.count else { completion?(); return }
        let action = actions[index]
        if [.moveMouse, .positionMouse, .clickMouse, .scrollMouse, .keystroke].contains(action.kind) {
            ignoreActivityUntil = Date().addingTimeInterval(1.5)
        }
        InputController.execute(action) { [weak self] error in
            guard let self else { return }
            if let error { self.onError?(error.localizedDescription) }
            if action.trigger == .interval { self.intervalExecutionCounts[action.id, default: 0] += 1 }
            self.execute(actions, at: index + 1, generation: generation, allowStopped: allowStopped, completion: completion)
        }
    }

    private var runningOnBattery: Bool {
        let powerSources = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        guard let sourceType = IOPSGetProvidingPowerSourceType(powerSources)?.takeRetainedValue() as String? else { return false }
        return sourceType == (kIOPSBatteryPowerValue as String)
    }

    private func beginPowerAssertion() {
        guard powerAssertion == 0 else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Move Mouse is running" as CFString,
            &powerAssertion
        )
        if result != kIOReturnSuccess {
            powerAssertion = 0
            onError?("macOS could not prevent system sleep (error \(result)).")
        }
    }

    private func endPowerAssertion() {
        guard powerAssertion != 0 else { return }
        IOPMAssertionRelease(powerAssertion)
        powerAssertion = 0
    }
}
