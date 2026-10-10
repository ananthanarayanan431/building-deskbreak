import SwiftUI

/// The icon shown in the menu bar.
struct MenuBarLabel: View {
    @ObservedObject var controller: AppController

    var body: some View {
        Image(systemName: symbolName)
            .accessibilityLabel(accessibilityText)
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
}
