import DeskBreakCore
import SwiftUI

/// The window shown when the menu bar icon is clicked.
struct MenuContentView: View {
    @ObservedObject var controller: AppController
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showingSettings {
                SettingsView(controller: controller) { showingSettings = false }
            } else {
                mainPage
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear {
            controller.refreshLoginItemState()
        }
    }

    // MARK: Main page

    private var mainPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DeskBreak").font(.headline)
                Spacer()
                StatusBadge(controller: controller)
            }

            // Re-renders once a second only while the window is open; nothing ticks when it is closed.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let summary = controller.todaySummary(now: context.date)
                VStack(alignment: .leading, spacing: 10) {
                    ReminderRow(kind: .water, controller: controller, count: summary.water)
                    ReminderRow(kind: .walk, controller: controller, count: summary.walk)
                }
            }

            warnings

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                if controller.isPaused {
                    MenuButton("Resume now", systemImage: "play.fill") { controller.resume() }
                } else {
                    MenuButton("Pause for 1 hour", systemImage: "pause.fill") { controller.pause() }
                }
                MenuButton("Settings…", systemImage: "gearshape") { showingSettings = true }
                MenuButton("Quit DeskBreak", systemImage: "power") { NSApp.terminate(nil) }
            }
        }
    }

    @ViewBuilder
    private var warnings: some View {
        if controller.loginItemState == .requiresApproval {
            WarningView(
                message: "Launch at login needs your approval in System Settings.",
                actionTitle: "Open Login Items",
                action: controller.openLoginItemSettings
            )
        }

        if let error = controller.lastError {
            WarningView(message: error, actionTitle: nil, action: nil)
        }
    }
}

// MARK: - Components

private struct ReminderRow: View {
    let kind: ReminderKind
    @ObservedObject var controller: AppController
    let count: DailySummary.Count

    var body: some View {
        let remaining = controller.remaining(for: kind)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind == .water ? "drop.fill" : "figure.walk")
                .foregroundStyle(kind == .water ? Color.blue : Color.green)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind == .water ? "Water" : "Walk").font(.body.weight(.medium))
                Text(nextText(remaining.regular))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let snooze = remaining.snooze {
                    Text("Snoozed, back in \(DurationText.short(snooze))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(count.done)/\(count.fired)")
                .font(.body.monospacedDigit())
                .accessibilityLabel("\(count.done) done out of \(count.fired) today")
        }
    }

    private func nextText(_ seconds: TimeInterval) -> String {
        let time = DurationText.short(seconds)
        if controller.isPaused || controller.activity != .active {
            return "Next in \(time) (paused)"
        }
        return "Next in \(time)"
    }
}

private struct StatusBadge: View {
    @ObservedObject var controller: AppController

    var body: some View {
        if let text {
            Text(text)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
    }

    private var text: String? {
        if let pauseUntil = controller.pauseUntil {
            return "Paused until \(pauseUntil.formatted(date: .omitted, time: .shortened))"
        }
        switch controller.activity {
        case .active: return nil
        case .away: return "Away"
        case .locked: return "Locked"
        }
    }
}

private struct WarningView: View {
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
    }
}

/// A full-width, menu-like button.
struct MenuButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Color.primary.opacity(0.08) : .clear))
        .onHover { hovering = $0 }
    }
}
