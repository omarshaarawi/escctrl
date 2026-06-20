import ServiceManagement

/// Launch-at-login via the modern `SMAppService` API (registers the .app itself as a login
/// item). Only works from a signed, bundled .app; a bare `swift run` binary can't register.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
