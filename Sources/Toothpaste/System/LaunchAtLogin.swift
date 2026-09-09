import ServiceManagement

/// Registers the app to start when the user logs in.
///
/// A clipboard manager that is not running captures nothing, so every reboot would
/// otherwise leave a hole in the history until it is started by hand.
///
/// `SMAppService.mainApp` needs a real, signed bundle — which is another reason the
/// app is installed to `~/Applications` rather than run out of the build directory.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the resulting state, which may differ from what was asked: the user can
    /// have the item disabled in System Settings, and that decision wins.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Toothpaste: could not \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)")
        }
        return isEnabled
    }

    /// What to show in the menu, including the case where the user has overridden us
    /// in System Settings.
    static var description: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "Start at login"
        case .requiresApproval: return "Start at login (needs approval in Settings)"
        case .notRegistered, .notFound: return "Start at login"
        @unknown default: return "Start at login"
        }
    }
}
