import SwiftUI

/// Panel shown when the menu bar icon is clicked.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            controls

            if !model.hasAccessibilityAccess {
                NoticeBox(symbol: "exclamationmark.triangle.fill", tint: .orange) {
                    Text("Accessibility access is needed to move the mouse and press keys.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Grant access…") { model.requestAccessibilityAccess() }
                        .controlSize(.small)
                }
            }

            if let error = model.errorMessage {
                NoticeBox(symbol: "xmark.octagon.fill", tint: .red) {
                    Text(error)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Dismiss") { model.errorMessage = nil }
                        .controlSize(.small)
                }
            }

            Divider()

            VStack(spacing: 8) {
                QuickToggle(title: "Keep Mac awake", symbol: "cup.and.saucer", isOn: $model.settings.keepAwake)
                QuickToggle(title: "Pause on battery", symbol: "bolt.slash", isOn: $model.settings.pauseOnBattery)
                QuickToggle(title: "Pause while I use the Mac", symbol: "hand.raised", isOn: $model.settings.autoPause)
            }

            Divider()

            HStack {
                Button {
                    model.openSettings()
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
                Spacer()
                Button {
                    model.quit()
                } label: {
                    Label("Quit", systemImage: "power")
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { model.refreshPermission() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(model.state.tint.opacity(0.18))
                Image(systemName: "computermouse.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(model.state == .stopped ? .secondary : model.state.tint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Move Mouse")
                    .font(.headline)
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.state.tint)
                        .frame(width: 7, height: 7)
                    Text(model.state.localizedTitle)
                    if model.state == .running, let nextRun = model.nextRun {
                        Text(verbatim: "·")
                        Text("next in") + Text(verbatim: " ") + Text(nextRun, style: .timer)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Spacer()
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                model.toggle()
            } label: {
                Group {
                    switch model.state {
                    case .running: Label("Pause", systemImage: "pause.fill")
                    case .paused: Label("Resume", systemImage: "play.fill")
                    case .stopped: Label("Start", systemImage: "play.fill")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                model.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 20)
            }
            .controlSize(.large)
            .disabled(model.state == .stopped)
            .help("Stop")
        }
    }
}

private struct QuickToggle: View {
    let title: LocalizedStringKey
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

/// Small coloured box for warnings and errors, used in the panel and in the settings window.
struct NoticeBox<Content: View>: View {
    let symbol: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundColor(tint)
            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .font(.callout)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }
}
