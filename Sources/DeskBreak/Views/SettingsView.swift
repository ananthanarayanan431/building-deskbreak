import DeskBreakCore
import SwiftUI

/// In-place settings page inside the menu window. Changes apply immediately.
struct SettingsView: View {
    @ObservedObject var controller: AppController
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: onDone) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Settings").font(.headline)
                Spacer()
                // Balances the Back button so the title stays centred.
                Label("Back", systemImage: "chevron.left").hidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                minutesStepper("Water every", \.waterInterval, range: ReminderSettings.intervalRange, step: 15)
                minutesStepper("Walk every", \.walkInterval, range: ReminderSettings.intervalRange, step: 15)
                minutesStepper("Snooze for", \.snoozeLength, range: ReminderSettings.snoozeRange, step: 5)
                minutesStepper("Answer within", \.responseWindow, range: ReminderSettings.responseWindowRange, step: 1)
                minutesStepper("Away after", \.idleThreshold, range: ReminderSettings.idleThresholdRange, step: 1)
            }

            Toggle("Launch at login", isOn: launchAtLoginBinding)
                .disabled(controller.loginItemState == .unavailable)

            HStack {
                Button("Restore defaults") { controller.updateSettings(.default) }
                    .disabled(controller.settings == .default)
                Spacer()
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { controller.loginItemState == .enabled || controller.loginItemState == .requiresApproval },
            set: { controller.setLaunchAtLogin($0) }
        )
    }

    private func minutesStepper(
        _ title: String,
        _ keyPath: WritableKeyPath<ReminderSettings, TimeInterval>,
        range: ClosedRange<TimeInterval>,
        step: Int
    ) -> some View {
        let minutes = Int(controller.settings[keyPath: keyPath] / 60)
        let lower = Int(range.lowerBound / 60)
        let upper = Int(range.upperBound / 60)
        return Stepper(
            value: Binding(
                get: { minutes },
                set: { newValue in
                    var updated = controller.settings
                    updated[keyPath: keyPath] = TimeInterval(newValue * 60)
                    controller.updateSettings(updated)
                }
            ),
            in: lower...upper,
            step: step
        ) {
            HStack {
                Text(title)
                Spacer()
                Text(DurationText.short(TimeInterval(minutes * 60)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
