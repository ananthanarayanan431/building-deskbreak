import AppKit
import DeskBreakCore
import SwiftUI

/// Shows each reminder as a small floating panel in the top-right corner, with the three answers
/// as buttons directly underneath.
///
/// System notifications put more than one action under an "Options" menu, so the app draws its own
/// panel instead. The panel never becomes key or activates the app, so it never takes keyboard focus
/// from whatever the user is typing in; it only receives clicks.
@MainActor
final class ReminderPanelController {
    var onResponse: ((UUID, ReminderResponse) -> Void)?

    /// Open panels, oldest first. Stacked downward from the top-right corner in this order.
    private var panels: [(recordID: UUID, panel: NSPanel)] = []
    private var screenObserver: NSObjectProtocol?

    private static let margin: CGFloat = 12
    private static let spacing: CGFloat = 10
    private static let width: CGFloat = 340

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    func show(_ record: ReminderRecord, isFollowUp: Bool, snoozeLength: TimeInterval) {
        remove(recordID: record.id)

        let recordID = record.id
        let view = ReminderPanelView(
            kind: record.kind,
            isFollowUp: isFollowUp,
            snoozeLength: snoozeLength
        ) { [weak self] response in
            self?.answer(recordID, with: response)
        }

        let hosting = ClickThroughHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = ReminderPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Keep reminders out of screen recordings and screen sharing where macOS honours it.
        panel.sharingType = .none
        panel.setAccessibilityLabel(record.kind == .water ? "Water reminder" : "Walk reminder")

        panels.append((recordID, panel))
        layout()
        panel.orderFrontRegardless()
    }

    func remove(recordID: UUID) {
        guard let index = panels.firstIndex(where: { $0.recordID == recordID }) else { return }
        panels.remove(at: index).panel.close()
        layout()
    }

    func removeAll() {
        for entry in panels {
            entry.panel.close()
        }
        panels.removeAll()
    }

    private func answer(_ recordID: UUID, with response: ReminderResponse) {
        remove(recordID: recordID)
        onResponse?(recordID, response)
    }

    /// Stacks the panels down from the top-right corner of the main screen's usable area.
    private func layout() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        var top = visible.maxY - Self.margin
        for entry in panels {
            let height = entry.panel.contentView?.fittingSize.height ?? entry.panel.frame.height
            let frame = NSRect(
                x: visible.maxX - Self.width - Self.margin,
                y: top - height,
                width: Self.width,
                height: height
            )
            entry.panel.setFrame(frame, display: true)
            top = frame.minY - Self.spacing
        }
    }
}

/// A panel that can never become key or main, so showing or clicking it never steals focus.
private final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on a button act immediately, even though the panel is never key.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Panel content

private struct ReminderPanelView: View {
    let kind: ReminderKind
    let isFollowUp: Bool
    let snoozeLength: TimeInterval
    let onAnswer: (ReminderResponse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: kind == .water ? "drop.fill" : "figure.walk")
                    .font(.title2)
                    .foregroundStyle(kind == .water ? Color.blue : Color.green)
                    .frame(width: 26)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if isFollowUp {
                        Text("Snoozed reminder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    onAnswer(.dismissed)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close without answering (counts as missed)")
                .accessibilityLabel("Close without answering")
            }

            HStack(spacing: 8) {
                Button("I did") { onAnswer(.done) }
                    .buttonStyle(.borderedProminent)
                Button("Not doing") { onAnswer(.skipped) }
                    .buttonStyle(.bordered)
                Spacer(minLength: 0)
                Button("Remind me in \(DurationText.setting(snoozeLength))") { onAnswer(.snoozed) }
                    .buttonStyle(.bordered)
            }
            .controlSize(.regular)
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }

    private var title: String {
        switch kind {
        case .water: "Drink some water"
        case .walk: "Time to walk"
        }
    }

    private var message: String {
        switch kind {
        case .water: "Time for a glass of water."
        case .walk: "Stand up and walk for a few minutes."
        }
    }
}
