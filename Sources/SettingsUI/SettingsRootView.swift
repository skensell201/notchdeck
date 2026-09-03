import AppKit
import Combine
import Preferences
import SwiftUI

/// The four tabs, in the order they were specified: what most people change, the
/// modules, the notch itself, and what the system has to say about it.
struct SettingsRootView: View {
    let preferences: Preferences
    let modules: ModulesViewModel
    let launchAtLogin: any LaunchAtLoginControlling
    let inspector: any PermissionInspecting

    /// Bumped whenever the window comes forward, to re-read permission statuses
    /// the user may have changed in System Settings while this window waited.
    @State private var permissionRefresh = 0

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(
                    preferences: preferences,
                    launchAtLogin: launchAtLogin,
                    accessibilityIsTrusted: inspector.accessibilityIsTrusted
                )
            }
            Tab("Modules", systemImage: "square.grid.2x2") {
                ModulesSettingsView(model: modules)
            }
            Tab("Notch", systemImage: "rectangle.topthird.inset.filled") {
                NotchSettingsView(preferences: preferences)
            }
            Tab("Permissions", systemImage: "hand.raised") {
                PermissionsSettingsView(inspector: inspector, refreshToken: permissionRefresh)
            }
        }
        .frame(width: 560, height: 420)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionRefresh += 1
        }
    }
}
