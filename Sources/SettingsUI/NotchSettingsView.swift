import AppKit
import CoreGraphics
import NotchCore
import Preferences
import SwiftUI

/// The notch NotchDeck draws for itself on displays that have none, and the
/// colour it fades to once it is open.
struct NotchSettingsView: View {
    let preferences: Preferences
    let inventory: any DisplayNotchInventorying

    /// Read at appearance and again whenever a display is attached, detached or
    /// reconfigured, so the note below the sliders describes the desk as it is.
    @State private var displays: [DisplayNotch] = []

    var body: some View {
        Form {
            Section {
                PointSlider(title: "Width", value: width, range: 120...600, step: 5)
                PointSlider(title: "Height", value: height, range: 20...60, step: 1)
            } header: {
                Text("Synthetic notch")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Used only on displays without a real notch — an external monitor, or a Mac that never had one. A display with its own notch always uses its own measurements.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let note = SyntheticNotchNote.text(for: displays) {
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Section {
                Toggle("Tint the expanded panel", isOn: tintIsOn)
                if preferences.notchTint != nil {
                    LabeledContent("Colour") {
                        ColorPicker("Colour", selection: tintColour, supportsOpacity: false)
                            .labelsHidden()
                    }
                    PercentSlider(title: "Strength", value: tintStrength)
                }
            } header: {
                Text("Panel tint")
            } footer: {
                Text("The top of the panel stays black whatever you pick — that band lies over the camera housing, and colour there would outline the notch instead of hiding it. The fade starts below the housing and reaches full strength at the bottom edge. The closed notch is never tinted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { displays = inventory.displays }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = inventory.displays
        }
    }

    /// Turning the tint off clears the stored colour rather than remembering it:
    /// a panel that is black again should look black to the next launch too.
    private var tintIsOn: Binding<Bool> {
        Binding(
            get: { preferences.notchTint != nil },
            set: { preferences.notchTint = $0 ? Self.startingTint : nil }
        )
    }

    private var tintColour: Binding<Color> {
        Binding(
            get: { Color(preferences.notchTint ?? Self.startingTint) },
            set: { preferences.notchTint = $0.notchTint ?? Self.startingTint }
        )
    }

    private var tintStrength: Binding<Double> {
        Binding(
            get: { preferences.notchTintStrength },
            set: { preferences.notchTintStrength = $0 }
        )
    }

    /// Where the picker opens: deep enough to read as bezel rather than as a
    /// coloured window, which is the failure mode of a bright tint.
    private static let startingTint = NotchTint(red: 0.169, green: 0.239, blue: 0.471)

    private var width: Binding<Double> {
        Binding(
            get: { preferences.syntheticNotchSize.width },
            set: { preferences.syntheticNotchSize = CGSize(width: $0, height: preferences.syntheticNotchSize.height) }
        )
    }

    private var height: Binding<Double> {
        Binding(
            get: { preferences.syntheticNotchSize.height },
            set: { preferences.syntheticNotchSize = CGSize(width: preferences.syntheticNotchSize.width, height: $0) }
        )
    }
}

/// A slider that shows both the value and the range it is confined to, so a
/// track that stops moving is explained rather than merely felt.
struct PointSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                // The slider keeps a label for VoiceOver and hides it on screen:
                // `LabeledContent` already draws the title in the row's leading
                // column, and AppKit draws a slider's own label too, which put
                // the word there twice.
                Slider(value: $value, in: range, step: step) {
                    Text(title)
                } minimumValueLabel: {
                    Text("\(Int(range.lowerBound))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("\(Int(range.upperBound))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .labelsHidden()
                Text("\(Int(value)) pt")
                    .font(.body.monospacedDigit())
                    .frame(width: 58, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}

private extension Color {
    init(_ tint: NotchTint) {
        self.init(red: tint.red, green: tint.green, blue: tint.blue)
    }

    /// Through sRGB explicitly: the picker can hand back a colour in any space,
    /// and reading components off the wrong one shifts the hue on the way to the
    /// notch. Nil when the conversion is not possible at all.
    var notchTint: NotchTint? {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return NotchTint(
            red: Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue: Double(srgb.blueComponent)
        )
    }
}

/// The strength slider: the same row as `PointSlider`, counted in percent.
struct PercentSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Slider(value: $value, in: 0...1, step: 0.05) {
                    Text(title)
                }
                .labelsHidden()
                Text("\(Int((value * 100).rounded())) %")
                    .font(.body.monospacedDigit())
                    .frame(width: 58, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}
