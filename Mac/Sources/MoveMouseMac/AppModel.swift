import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// Single source of truth for the UI. Every change to `settings` is saved automatically
/// (debounced) and pushed to the automation engine — there is no "Save" button any more.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let engine = AutomationEngine()

    @Published var settings: AppSettings
    @Published private(set) var state: AutomationEngine.State = .stopped
    @Published private(set) var nextRun: Date?
    @Published private(set) var hasAccessibilityAccess = InputController.hasAccessibilityAccess
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var errorMessage: String?
    @Published var selectedSection: SettingsSection = .general
    /// Selected row in Settings > Actions. Kept here rather than in a SwiftUI @State: @State is a macro
    /// in recent SDKs and fails to build with toolchains that lack the SwiftUI macro plugin.
    @Published var selectedActionID: UUID?

    private let isFirstLaunch: Bool
    /// True when an existing settings file could not be read: it is backed up before the first save.
    private var mustBackUpUnreadableSettings: Bool
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let fileExists = FileManager.default.fileExists(atPath: SettingsStore.settingsURL.path)
        var loaded = AppSettings()
        var loadError: String?
        do {
            loaded = try SettingsStore.load()
        } catch {
            loadError = String(localized: "Could not read the settings file, defaults are in use. The old file will be kept as settings.json.bak.")
                + " (\(error.localizedDescription))"
        }
        isFirstLaunch = !fileExists
        mustBackUpUnreadableSettings = loadError != nil
        settings = loaded
        // errorMessage has a default value, so it can only be set once every stored property is initialised.
        errorMessage = loadError

        engine.configure(loaded)
        engine.onStateChanged = { [weak self] state in self?.state = state }
        engine.onNextRunChanged = { [weak self] date in self?.nextRun = date }
        engine.onError = { [weak self] message in
            NSLog("Move Mouse: %@", message)
            guard let self else { return }
            // The missing-permission case already has its own (localized) notice with a button:
            // showing the engine's English message as well would just duplicate it.
            if message == InputControllerError.accessibilityPermissionRequired.localizedDescription {
                self.hasAccessibilityAccess = false
                return
            }
            self.errorMessage = message
        }

        $settings
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] settings in self?.persist(settings) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refreshPermission() }
            .store(in: &cancellables)
    }

    func didFinishLaunching() {
        // A menu-bar-only app is easy to miss: show the settings the first time, or when permission is missing.
        if isFirstLaunch {
            openSettings(section: hasAccessibilityAccess ? .general : .permissions)
        }
    }

    // MARK: - Run control

    func toggle() {
        if state == .running {
            engine.pause()
        } else {
            engine.configure(settings)
            engine.start()
        }
    }

    func stop() { engine.stop() }

    /// Turning auto-pause on also turns auto-resume on: auto-pause alone pauses at the first touch of the
    /// mouse and never resumes, which looks like the app does not work.
    var autoPauseBinding: Binding<Bool> {
        Binding(get: { self.settings.autoPause }, set: { enabled in
            self.settings.autoPause = enabled
            if enabled { self.settings.autoResume = true }
        })
    }

    func quit() {
        saveNow()
        engine.stop()
        NSApp.terminate(nil)
    }

    // MARK: - Windows

    func openSettings(section: SettingsSection? = nil) {
        SettingsWindowController.shared.show(model: self, section: section)
    }

    func revealSettingsFile() {
        let url = SettingsStore.settingsURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    // MARK: - Permissions

    func refreshPermission() {
        let current = InputController.hasAccessibilityAccess
        if current != hasAccessibilityAccess { hasAccessibilityAccess = current }
        if current, errorMessage == InputControllerError.accessibilityPermissionRequired.localizedDescription {
            errorMessage = nil
        }
    }

    func requestAccessibilityAccess() {
        _ = InputController.requestAccessibilityAccess()
        refreshPermission()
        if !hasAccessibilityAccess { openAccessibilitySettings() }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Login item

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled && SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !enabled && SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = String(localized: "Could not change the login item. Move the app to the Applications folder and try again.")
                + " (\(error.localizedDescription))"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        settings.launchAtLogin = launchAtLogin
    }

    // MARK: - Persistence

    func saveNow() { persist(settings) }

    private func persist(_ settings: AppSettings) {
        engine.configure(settings)
        do {
            if mustBackUpUnreadableSettings {
                let url = SettingsStore.settingsURL
                let backup = url.appendingPathExtension("bak")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.copyItem(at: url, to: backup)
                mustBackUpUnreadableSettings = false
            }
            try SettingsStore.save(settings)
        } catch {
            errorMessage = String(localized: "Could not save settings.") + " (\(error.localizedDescription))"
        }
    }

    // MARK: - Bindings to list items by id (safe when items are deleted while a view is on screen)

    func actionBinding(_ id: UUID) -> Binding<AutomationAction> {
        Binding(
            get: { self.settings.actions.first { $0.id == id } ?? AutomationAction() },
            set: { newValue in
                if let index = self.settings.actions.firstIndex(where: { $0.id == id }) { self.settings.actions[index] = newValue }
            }
        )
    }

    func scheduleBinding(_ id: UUID) -> Binding<ScheduledRule> {
        Binding(
            get: { self.settings.schedules.first { $0.id == id } ?? ScheduledRule() },
            set: { newValue in
                if let index = self.settings.schedules.firstIndex(where: { $0.id == id }) { self.settings.schedules[index] = newValue }
            }
        )
    }

    func blackoutBinding(_ id: UUID) -> Binding<BlackoutRule> {
        Binding(
            get: { self.settings.blackouts.first { $0.id == id } ?? BlackoutRule() },
            set: { newValue in
                if let index = self.settings.blackouts.firstIndex(where: { $0.id == id }) { self.settings.blackouts[index] = newValue }
            }
        )
    }
}

// MARK: - Presentation helpers

extension AutomationEngine.State {
    var localizedTitle: String {
        switch self {
        case .running: return String(localized: "Running")
        case .paused: return String(localized: "Paused")
        case .stopped: return String(localized: "Stopped")
        }
    }

    var menuBarSymbol: String {
        switch self {
        case .running: return "cursorarrow.motionlines"
        case .paused: return "pause.circle"
        case .stopped: return "cursorarrow"
        }
    }

    var tint: Color {
        switch self {
        case .running: return .green
        case .paused: return .orange
        case .stopped: return .secondary
        }
    }
}

extension ActionKind {
    var localizedTitle: String {
        switch self {
        case .moveMouse: return String(localized: "Move mouse")
        case .positionMouse: return String(localized: "Position mouse")
        case .clickMouse: return String(localized: "Click mouse")
        case .scrollMouse: return String(localized: "Scroll mouse")
        case .keystroke: return String(localized: "Keystroke")
        case .runCommand: return String(localized: "Run command")
        case .runScript: return String(localized: "Run shell script")
        case .activateApplication: return String(localized: "Activate application")
        case .sleep: return String(localized: "Wait")
        }
    }

    var symbol: String {
        switch self {
        case .moveMouse: return "cursorarrow.motionlines"
        case .positionMouse: return "scope"
        case .clickMouse: return "cursorarrow.click"
        case .scrollMouse: return "scroll"
        case .keystroke: return "keyboard"
        case .runCommand: return "terminal"
        case .runScript: return "doc.text"
        case .activateApplication: return "macwindow"
        case .sleep: return "hourglass"
        }
    }

    var defaultParameter: String {
        switch self {
        case .moveMouse: return "square, 10"
        case .positionMouse: return "400, 300"
        case .clickMouse: return "left"
        case .scrollMouse: return "down, 100"
        case .keystroke: return "49"
        case .runCommand, .runScript, .activateApplication: return ""
        case .sleep: return "1"
        }
    }

    var localizedHelp: String {
        switch self {
        case .moveMouse: return String(localized: "Direction and distance (1–500), e.g. square, 10. Directions: square, none, random, north, south, east, west, northeast, northwest, southeast, southwest, up and down, left and right.")
        case .positionMouse: return String(localized: "Screen coordinates as x, y — e.g. 400, 300.")
        case .clickMouse: return String(localized: "Button (left, middle, right) and optional hold time in seconds — e.g. left, 0.5.")
        case .scrollMouse: return String(localized: "Direction (up, down, left, right, random) and distance — e.g. down, 100.")
        case .keystroke: return String(localized: "macOS virtual key codes separated by commas — e.g. 49 for Space.")
        case .runCommand: return String(localized: "Full path of the executable. Arguments support shell-style quotes.")
        case .runScript: return String(localized: "Path of a shell script, run with /bin/zsh without opening Terminal.")
        case .activateApplication: return String(localized: "Bundle identifier (e.g. com.apple.Safari) or path of an .app.")
        case .sleep: return String(localized: "Seconds to wait before the next action.")
        }
    }
}

extension ActionTrigger {
    var localizedTitle: String {
        switch self {
        case .start: return String(localized: "When starting")
        case .interval: return String(localized: "Every interval")
        case .stop: return String(localized: "When stopping")
        }
    }
}
