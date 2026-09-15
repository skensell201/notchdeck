import Preferences
import SwiftUI

/// Launch at login, the volume overlay, Esc, and the two intervals that decide
/// how eager the notch feels.
struct GeneralSettingsView: View {
    @Bindable var preferences: Preferences
    let launchAtLogin: any LaunchAtLoginControlling
    let accessibilityIsTrusted: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Launch NotchDeck at login", isOn: launchAtLoginBinding)
                if let failure = launchAtLogin.failureDescription {
                    Text(failure)
                        .font(.callout)
                        .foregroundStyle(.red)
                    Text("Moving NotchDeck to your Applications folder usually fixes this.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Hide the system volume overlay", isOn: $preferences.suppressVolumeHUD)
                Text("Stops the square that appears in the middle of the screen when you change the volume. NotchDeck puts nothing in its place — the keys still work, they just stop announcing themselves.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Dismiss the notch with Esc", isOn: $preferences.dismissWithEscape)
                Text(escapeExplanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Timing") {
                MillisecondSlider(
                    title: "Hover dwell",
                    caption: "How long the pointer has to rest on the notch before it opens.",
                    value: $preferences.hoverDwellMilliseconds,
                    range: 60...1000,
                    step: 10
                )
                MillisecondSlider(
                    title: "Exit grace",
                    caption: "How long the notch stays open after the pointer leaves.",
                    value: $preferences.exitGraceMilliseconds,
                    range: 0...2000,
                    step: 10
                )
            }
        }
        .formStyle(.grouped)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        // Built by hand rather than with `@Bindable`, because `launchAtLogin` is
        // an existential the app supplies.
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.isEnabled = $0 }
        )
    }

    private var escapeExplanation: String {
        // Named plainly: this is the one feature that costs a permission, and a
        // switch that quietly does nothing is worse than a sentence.
        if accessibilityIsTrusted {
            "Watching for Esc needs Accessibility access, which NotchDeck already has."
        } else {
            "Watching for Esc needs Accessibility access, which NotchDeck does not have yet. Everything else works without it."
        }
    }
}

/// A slider that shows the value it is setting, because "somewhere around a
/// fifth of a second" is not something a bare track can say.
struct MillisecondSlider: View {
    let title: String
    let caption: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent {
                HStack(spacing: 8) {
                    Slider(value: doubleValue, in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step))
                    Text("\(value) ms")
                        .font(.body.monospacedDigit())
                        .frame(width: 58, alignment: .trailing)
                }
            } label: {
                Text(title)
            }
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var doubleValue: Binding<Double> {
        Binding(
            get: { Double(value) },
            set: { value = Int($0.rounded()) }
        )
    }
}
