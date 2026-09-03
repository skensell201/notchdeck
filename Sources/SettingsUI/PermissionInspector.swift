import AVFoundation
import AppKit
import ApplicationServices
import EventKit
import NotchUI

/// Reads what the user has already granted, and nothing else.
///
/// Every call here is a status read: none of them shows a prompt, so opening the
/// Permissions tab cannot ask for anything. Asking belongs to the module that
/// needs the access, at the moment it needs it.
@MainActor
public protocol PermissionInspecting: Sendable {
    func status(of permission: ModulePermission) -> PermissionStatus
    /// Whether the app may install the global key monitor the Esc shortcut needs.
    var accessibilityIsTrusted: Bool { get }
}

public struct SystemPermissionInspector: PermissionInspecting {
    public init() {}

    public func status(of permission: ModulePermission) -> PermissionStatus {
        switch permission {
        case .camera:
            Self.translate(AVCaptureDevice.authorizationStatus(for: .video))
        case .calendar:
            Self.translate(EKEventStore.authorizationStatus(for: .event))
        }
    }

    public var accessibilityIsTrusted: Bool {
        // The no-prompt form: passing the prompt option here would put a system
        // dialog in front of a window the user opened to read a status.
        AXIsProcessTrusted()
    }

    private static func translate(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .blocked
        }
    }

    private static func translate(_ status: EKAuthorizationStatus) -> PermissionStatus {
        switch status {
        // Read-only access is all the agenda module ever wanted, so it counts.
        case .fullAccess, .authorized: .granted
        case .notDetermined: .notDetermined
        default: .blocked
        }
    }
}
