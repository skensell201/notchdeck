import CoreGraphics
import Preferences
import SwiftUI

/// The notch NotchDeck draws for itself on displays that have none.
struct NotchSettingsView: View {
    let preferences: Preferences

    var body: some View {
        Form {
            Section {
                PointSlider(title: "Width", value: width, range: 120...600, step: 5)
                PointSlider(title: "Height", value: height, range: 20...60, step: 1)
            } header: {
                Text("Synthetic notch")
            } footer: {
                Text("Used only on displays without a real notch — an external monitor, or a Mac that never had one. A display with its own notch always uses its own measurements.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

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
                Text("\(Int(value)) pt")
                    .font(.body.monospacedDigit())
                    .frame(width: 58, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}
