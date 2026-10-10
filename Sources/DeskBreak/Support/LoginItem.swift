import ServiceManagement

/// Launch at login through `SMAppService` (macOS 13+). No helper app or LaunchAgent file is installed.
@MainActor
enum LoginItem {
    enum State: Equatable {
        case enabled
        case disabled
        /// Registered, but the user must allow it in System Settings → General → Login Items.
        case requiresApproval
        case unavailable
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        // `.notFound` is also what an app that has never registered reports, so it stays toggleable;
        // if registering really fails, `setLaunchAtLogin` surfaces the error.
        case .notRegistered, .notFound: .disabled
        case .requiresApproval: .requiresApproval
        @unknown default: .unavailable
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
