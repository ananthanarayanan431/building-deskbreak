import AppKit
import SwiftUI

/// The icon shown in the menu bar.
struct MenuBarLabel: View {
    @ObservedObject var controller: AppController

    var body: some View {
        icon
            .accessibilityLabel(accessibilityText)
    }

    /// While counting, a filled blue drop; while paused or away, the standard monochrome symbol,
    /// so the colour itself signals that reminders are running.
    @ViewBuilder
    private var icon: some View {
        if let image = Self.blueDrop, !controller.isPaused, controller.activity == .active {
            Image(nsImage: image)
        } else {
            Image(systemName: symbolName)
        }
    }

    private var symbolName: String {
        if controller.isPaused { return "pause.circle" }
        switch controller.activity {
        case .active: return "drop"
        case .away, .locked: return "moon.zzz"
        }
    }

    private var accessibilityText: String {
        if controller.isPaused { return "DeskBreak, paused" }
        switch controller.activity {
        case .active: return "DeskBreak"
        case .away, .locked: return "DeskBreak, away"
        }
    }

    /// The menu bar renders SwiftUI images as templates and drops their colour, so the coloured
    /// symbol is built as a non-template `NSImage`.
    private static let blueDrop: NSImage? = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.systemBlue]))
        let image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = false
        return image
    }()
}
