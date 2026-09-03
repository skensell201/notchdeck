import AppKit
import SwiftUI

/// A capability a module needs the user to grant.
///
/// Requesting camera or calendar access without the matching `Info.plist` string
/// does not fail politely — TCC terminates the process — so the description keys
/// and the code that triggers the request must ship together.
public enum ModulePermission: Equatable, Sendable {
    case camera
    case calendar

    public var title: String {
        switch self {
        case .camera: "Camera access is needed"
        case .calendar: "Calendar access is needed"
        }
    }

    public var explanation: String {
        switch self {
        case .camera: "NotchDeck shows a live preview so you can check yourself before a call. The camera runs only while this tab is open."
        case .calendar: "NotchDeck reads your events to show what is coming up. Nothing is changed and nothing leaves your Mac."
        }
    }

    /// The exact System Settings pane, so a denied user is one click from fixing
    /// it rather than hunting through Privacy & Security.
    public var settingsURL: URL? {
        switch self {
        case .camera: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
        case .calendar: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        }
    }
}

public enum PermissionStatus: Equatable, Sendable {
    case notDetermined
    case granted
    /// Denied or restricted: asking again does nothing, so the only way forward
    /// is System Settings.
    case blocked
}

/// The empty state a module shows instead of its content while it lacks access.
public struct PermissionPrompt: View {
    private let permission: ModulePermission
    private let status: PermissionStatus
    private let onRequest: () -> Void

    public init(permission: ModulePermission, status: PermissionStatus, onRequest: @escaping () -> Void) {
        self.permission = permission
        self.status = status
        self.onRequest = onRequest
    }

    public var body: some View {
        VStack(spacing: 5) {
            Text(permission.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            Text(permission.explanation)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: 320)
            Button(status == .blocked ? "Open System Settings" : "Allow") {
                if status == .blocked {
                    if let url = permission.settingsURL {
                        NSWorkspace.shared.open(url)
                    }
                } else {
                    onRequest()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(0.15)))
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
