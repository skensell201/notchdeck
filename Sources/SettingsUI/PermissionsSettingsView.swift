import AppKit
import NotchUI
import SwiftUI

/// What the user has granted, and one click to the pane where it can be changed.
///
/// Read-only on purpose. An app can ask for access it does not have, but it
/// cannot take back access it does — a switch here would be a control that only
/// works in one direction while pretending to work in both.
struct PermissionsSettingsView: View {
    let inspector: any PermissionInspecting
    /// Re-read when the window comes back to the front: the user grants access
    /// in System Settings, then returns here expecting the row to agree.
    let refreshToken: Int

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    name: "Camera",
                    usage: "The mirror module shows a live preview while its tab is open.",
                    permission: .camera,
                    status: inspector.status(of: .camera)
                )
                PermissionRow(
                    name: "Calendar",
                    usage: "The agenda module reads your events to show what is coming up.",
                    permission: .calendar,
                    status: inspector.status(of: .calendar)
                )
            } footer: {
                Text("NotchDeck can ask for access but cannot take it back, so these are shown, not set. System Settings is where they change.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .id(refreshToken)
    }
}

private struct PermissionRow: View {
    let name: String
    let usage: String
    let permission: ModulePermission
    let status: PermissionStatus

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Label(statusText, systemImage: symbolName)
                    .foregroundStyle(statusColor)
                Button("Open System Settings") {
                    if let url = permission.settingsURL {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(usage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        switch status {
        case .granted: "Allowed"
        case .notDetermined: "Not yet asked"
        case .blocked: "Denied"
        }
    }

    private var symbolName: String {
        switch status {
        case .granted: "checkmark.circle.fill"
        case .notDetermined: "questionmark.circle"
        case .blocked: "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .granted: .green
        case .notDetermined: .secondary
        case .blocked: .red
        }
    }
}
