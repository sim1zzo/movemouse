# Move Mouse for macOS

This is a separate native macOS app. The existing Windows/WPF project is unchanged. It requires macOS 13 or later and Swift 5.9 or later to build.

This is an initial macOS port, not full feature parity with the Windows application. The core automation, schedules, and sleep-prevention workflow is available; remaining differences are listed below.

## Build and package

From this directory:

```sh
swift build
bash scripts/test-models.sh
bash scripts/package-app.sh
```

The package script builds a universal Apple Silicon/Intel app and produces `build/Move Mouse.app`, a ZIP archive, and a DMG with an Applications shortcut. To create a Developer ID-signed app, set `SIGNING_IDENTITY` to the installed Developer ID Application certificate name before packaging; Apple notarization additionally requires Apple Developer credentials and a notarization submission.

Unsigned builds are intended for local testing. macOS Gatekeeper may warn or block an unsigned download. Do not bypass that warning for an app whose source you do not trust.

## Interface

Move Mouse lives only in the menu bar (no Dock icon). Click its icon for a panel with the current state, Start/Pause/Stop and quick toggles; **Settings…** (⌘,) opens a window with General, Actions, Schedules, Blackouts and Permissions sections. Changes are saved automatically. The interface is available in English and Italian and follows the macOS system language.

## Permissions

Mouse and keyboard simulation requires **System Settings > Privacy & Security > Accessibility** permission. Use **Grant access…** in Settings > Permissions, enable Move Mouse in System Settings, then return to the app. Without this permission, mouse and keyboard actions are unavailable; schedules and the system-sleep assertion can still be used.

## macOS feature notes

- Mouse movement/positioning, clicking (including holds), scrolling, keystrokes, delays, command/script execution, application activation, interval execution, local-time weekday schedules and blackout windows, user-activity auto-pause/resume, battery pause, login launch, and preventing idle system sleep are implemented with macOS APIs.
- Command and shell-script actions start without a Terminal window. Shell scripts are run through `/bin/zsh`. Command arguments support quoted values.
- Application activation accepts a running or installed app's bundle identifier or an `.app` path.
- Not ported: Windows session-lock handling, active-window title matching, Windows audio-device volume handling, the Windows-only PowerShell action, custom mouse/window themes, taskbar progress, window-title/icon overrides, and Windows update integration. Some have different macOS APIs and may be added separately.
- Windows-only presentation features (custom mouse/window themes, taskbar progress, window-title/icon overrides, and Windows update integration) are not included. Quartz advanced schedules remain Windows-only for now.
- Settings are stored in `~/Library/Application Support/MoveMouse/settings.json`. Existing Windows XML settings are not imported; action key values use macOS virtual key codes, not Windows virtual key codes.
- Scheduled times use the Mac's local time zone. Windows Quartz advanced cron expressions are not imported.

Report platform-specific issues at the repository's issue tracker.
