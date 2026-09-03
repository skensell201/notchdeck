import AppKit
import NotchCore
import NotchUI
import Preferences
import Support
import SwiftUI

/// The settings window: one window, reused, and the only part of NotchDeck that
/// activates the app.
///
/// The notch panel is deliberately non-activating — it never becomes key, so it
/// never steals focus from whatever the user is typing in. That makes it the
/// wrong place for a text field or a keyboard-driven list, and makes this window
/// the one place ordinary keyboard input has to work. Hence the explicit
/// activation: an accessory app that only orders a window front gets a window
/// the user can see and cannot type into.
@MainActor
public final class SettingsWindowController {
    private let logger = Log.make("settings")
    private let preferences: Preferences
    private let registry: ModuleRegistry
    private let launchAtLogin: any LaunchAtLoginControlling
    private let inspector: any PermissionInspecting
    private var window: NSWindow?

    public init(
        preferences: Preferences,
        registry: ModuleRegistry,
        launchAtLogin: any LaunchAtLoginControlling,
        inspector: any PermissionInspecting = SystemPermissionInspector()
    ) {
        self.preferences = preferences
        self.registry = registry
        self.launchAtLogin = launchAtLogin
        self.inspector = inspector
    }

    /// Shows the window, or brings the existing one forward. Safe to call from a
    /// menu item as often as the user clicks it.
    public func show() {
        let window = window ?? makeWindow()
        self.window = window
        // Order matters: an accessory app has to be activated before the window
        // can take key, or it comes up in front and stays unresponsive.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Modules the settings window can name. Taken from the registry so a module
    /// only has to be registered once.
    private var descriptors: [SettingsModuleDescriptor] {
        registry.layout.order.compactMap { id in
            guard let module = registry.module(id) else { return nil }
            return SettingsModuleDescriptor(id: id, title: module.title, symbolName: module.symbolName)
        }
    }

    private func makeWindow() -> NSWindow {
        let model = ModulesViewModel(
            descriptors: descriptors,
            layout: registry.layout,
            commit: { [registry, preferences] layout in
                // The running notch first, so the change is visible before the
                // write; then the store, so it survives a relaunch.
                registry.apply(layout)
                preferences.moduleLayout = layout
            }
        )

        let root = SettingsRootView(
            preferences: preferences,
            modules: model,
            launchAtLogin: launchAtLogin,
            inspector: inspector
        )

        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "NotchDeck Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        // Closing settings must not destroy the object the menu item reopens.
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("NotchDeckSettings")
        logger.notice("settings window created")
        return window
    }
}
