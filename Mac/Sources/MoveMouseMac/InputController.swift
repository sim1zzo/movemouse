import AppKit
import ApplicationServices
import Foundation

enum InputControllerError: LocalizedError {
    case accessibilityPermissionRequired
    case invalidAction(String)
    case eventCouldNotBeCreated

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "Move Mouse needs Accessibility permission to simulate mouse or keyboard input. Enable it in System Settings > Privacy & Security > Accessibility, then try again."
        case .invalidAction(let message): return message
        case .eventCouldNotBeCreated: return "macOS could not create the requested input event."
        }
    }
}

enum InputController {
    static var hasAccessibilityAccess: Bool { CGPreflightPostEventAccess() }

    static func requestAccessibilityAccess() -> Bool {
        CGRequestPostEventAccess()
    }

    static func execute(_ action: AutomationAction, completion: @escaping (Error?) -> Void) {
        do {
            switch action.kind {
            case .moveMouse:
                try moveMouse(action.parameter)
                completion(nil)
            case .positionMouse:
                try positionMouse(action.parameter)
                completion(nil)
            case .clickMouse:
                try clickMouse(action.parameter, completion: completion)
            case .scrollMouse:
                try scrollMouse(action.parameter)
                completion(nil)
            case .keystroke:
                try pressKeys(action.parameter)
                completion(nil)
            case .runCommand, .runScript:
                try launchCommand(action, completion: completion)
            case .activateApplication:
                try activateApplication(action.parameter, completion: completion)
            case .sleep:
                guard let seconds = Double(action.parameter), seconds >= 0 else {
                    throw InputControllerError.invalidAction("Wait duration must be a non-negative number of seconds.")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { completion(nil) }
            }
        } catch {
            completion(error)
        }
    }

    private static func requireAccess() throws {
        guard hasAccessibilityAccess else { throw InputControllerError.accessibilityPermissionRequired }
    }

    private static func moveMouse(_ value: String) throws {
        try requireAccess()
        let parts = value.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let distance = Int(parts[1]), (1...500).contains(distance) else {
            throw InputControllerError.invalidAction("Move mouse expects a direction and distance, for example: square, 10 (distance 1–500).")
        }

        let direction = parts[0].lowercased()
        let directions: [String: [(CGFloat, CGFloat)]] = [
            "none": [(0, 0)],
            "north": [(0, -1)], "northeast": [(1, -1)], "east": [(1, 0)], "southeast": [(1, 1)],
            "south": [(0, 1)], "southwest": [(-1, 1)], "west": [(-1, 0)], "northwest": [(-1, -1)],
            "square": [(1, 0), (0, 1), (-1, 0), (0, -1)],
            "up and down": [(0, -1), (0, 1)], "down and up": [(0, 1), (0, -1)],
            "left and right": [(-1, 0), (1, 0)], "right and left": [(1, 0), (-1, 0)]
        ]
        guard let path = directions[direction] ?? (direction == "random" ? [] : nil) else {
            throw InputControllerError.invalidAction("Unknown mouse direction '\(parts[0])'.")
        }

        var point = CGEvent(source: nil)?.location ?? .zero
        let steps = direction == "none" ? 1 : distance
        if direction == "random" {
            let choices: [(CGFloat, CGFloat)] = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]
            var remaining = distance
            while remaining > 0 {
                let segment = min(remaining, Int.random(in: 1...min(20, remaining)))
                let vector = choices[Int.random(in: 0..<choices.count)]
                try postMovement(vector, point: &point, steps: segment)
                remaining -= segment
            }
            return
        }
        for (dx, dy) in path {
            try postMovement((dx, dy), point: &point, steps: steps)
        }
    }

    private static func postMovement(_ vector: (CGFloat, CGFloat), point: inout CGPoint, steps: Int) throws {
        for _ in 0..<steps {
            point = CGPoint(x: point.x + vector.0, y: point.y + vector.1)
            guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
                throw InputControllerError.eventCouldNotBeCreated
            }
            event.post(tap: .cghidEventTap)
            // Posting all steps at once made the movement instantaneous and invisible (a "square" ends where it
            // started); a short pause per step makes it a real, perceptible movement.
            usleep(4_000)
        }
    }

    private static func positionMouse(_ value: String) throws {
        try requireAccess()
        let coordinates = value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard coordinates.count == 2 else {
            throw InputControllerError.invalidAction("Position mouse expects x and y coordinates, for example: 400, 300.")
        }
        let result = CGWarpMouseCursorPosition(CGPoint(x: coordinates[0], y: coordinates[1]))
        guard result == .success else { throw InputControllerError.invalidAction("macOS could not move the pointer to that screen position.") }
    }

    private static func clickMouse(_ value: String, completion: @escaping (Error?) -> Void) throws {
        try requireAccess()
        let parts = value.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let name = parts.first ?? ""
        let holdSeconds = parts.count == 2 ? (Double(parts[1]) ?? -1) : 0
        guard holdSeconds >= 0, holdSeconds <= 30 else {
            throw InputControllerError.invalidAction("Click hold duration must be between 0 and 30 seconds.")
        }
        let button: CGMouseButton
        let down: CGEventType
        let up: CGEventType
        switch name {
        case "left": (button, down, up) = (.left, .leftMouseDown, .leftMouseUp)
        case "middle": (button, down, up) = (.center, .otherMouseDown, .otherMouseUp)
        case "right": (button, down, up) = (.right, .rightMouseDown, .rightMouseUp)
        default: throw InputControllerError.invalidAction("Mouse button must be left, middle, or right.")
        }
        let point = CGEvent(source: nil)?.location ?? .zero
        guard let downEvent = CGEvent(mouseEventSource: nil, mouseType: down, mouseCursorPosition: point, mouseButton: button),
              let upEvent = CGEvent(mouseEventSource: nil, mouseType: up, mouseCursorPosition: point, mouseButton: button) else {
            throw InputControllerError.eventCouldNotBeCreated
        }
        downEvent.post(tap: .cghidEventTap)
        if holdSeconds > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + holdSeconds) {
                upEvent.post(tap: .cghidEventTap)
                completion(nil)
            }
        } else {
            upEvent.post(tap: .cghidEventTap)
            completion(nil)
        }
    }

    private static func scrollMouse(_ value: String) throws {
        try requireAccess()
        let parts = value.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard parts.count == 2, let amount = Int32(parts[1]), amount > 0 else {
            throw InputControllerError.invalidAction("Scroll expects a direction and positive distance, for example: down, 100.")
        }
        let directionChoices = ["up", "down", "left", "right"]
        let direction = parts[0] == "random" ? directionChoices[Int.random(in: 0..<directionChoices.count)] : parts[0]
        let vertical = direction == "up" ? amount : direction == "down" ? -amount : 0
        let horizontal = direction == "right" ? amount : direction == "left" ? -amount : 0
        guard ["up", "down", "left", "right"].contains(direction) else {
            throw InputControllerError.invalidAction("Scroll direction must be up, down, left, or right.")
        }
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: vertical, wheel2: horizontal, wheel3: 0) else {
            throw InputControllerError.eventCouldNotBeCreated
        }
        event.post(tap: .cghidEventTap)
    }

    private static func pressKeys(_ value: String) throws {
        try requireAccess()
        let keys = value.split(separator: ",").compactMap { UInt16($0.trimmingCharacters(in: .whitespaces)) }
        guard !keys.isEmpty, keys.count == value.split(separator: ",").count else {
            throw InputControllerError.invalidAction("Keystroke expects one or more macOS virtual key codes separated by commas (for example: 49).")
        }
        for key in keys {
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) else {
                throw InputControllerError.eventCouldNotBeCreated
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    private static func launchCommand(_ action: AutomationAction, completion: @escaping (Error?) -> Void) throws {
        let path = action.parameter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw InputControllerError.invalidAction("Choose a command or script path.") }
        let process = Process()
        if action.kind == .runScript {
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [path] + (try parseArguments(action.arguments))
        } else {
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = try parseArguments(action.arguments)
        }
        if action.waitForExit {
            process.terminationHandler = { process in
                DispatchQueue.main.async {
                    completion(process.terminationStatus == 0 ? nil : InputControllerError.invalidAction("The command exited with status \(process.terminationStatus)."))
                }
            }
        }
        try process.run()
        if !action.waitForExit { completion(nil) }
    }

    private static func parseArguments(_ input: String) throws -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for character in input {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" && quote != "'" {
                escaped = true
            } else if let activeQuote = quote {
                if character == activeQuote { quote = nil } else { current.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        guard !escaped, quote == nil else {
            throw InputControllerError.invalidAction("Command arguments contain an unfinished quote or escape.")
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func activateApplication(_ value: String, completion: @escaping (Error?) -> Void) throws {
        let identifier = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { throw InputControllerError.invalidAction("Enter an application bundle identifier or .app path.") }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first {
            guard running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) else {
                throw InputControllerError.invalidAction("macOS could not activate '\(identifier)'.")
            }
            completion(nil)
            return
        }
        if let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            NSWorkspace.shared.openApplication(at: applicationURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: { _, error in
                DispatchQueue.main.async { completion(error) }
            })
            return
        }
        let url = URL(fileURLWithPath: identifier)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw InputControllerError.invalidAction("No running app was found with bundle ID '\(identifier)', and the path does not exist.")
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: { _, error in
            DispatchQueue.main.async { completion(error) }
        })
    }
}
