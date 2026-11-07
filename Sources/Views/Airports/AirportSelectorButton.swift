import SwiftUI

struct AirportSelectorButton: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Binding var airport: Airport?
    @Binding var fallbackCode: String
    var cornerRadius: CGFloat = 17
    var monochrome: Bool = false
    @State private var isPresented = false
    @StateObject private var locator = DepartureAirportLocationResolver()

    var body: some View {
        HStack(spacing: 0) {
            Button {
                isPresented = true
                IumrahHaptics.soft()
            } label: {
                HStack(spacing: 13) {
                    if monochrome {
                        Image(systemName: "airplane.departure")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.iumrahSignatureBlack)
                            .frame(width: 42, height: 42)
                            .background(Color.iumrahRaisedBackground, in: Circle())
                    } else {
                        IumrahIconBadge(
                            systemName: "airplane.departure",
                            role: .travel,
                            size: 38,
                            symbolSize: 17,
                            shape: .circle
                        )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text("airport_title", settings.language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let airport {
                            Text(airport.compactTitle)
                                .font(.headline)
                            Text(airport.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text(fallbackCode.isEmpty ? L10n.text("airport_search_title", settings.language) : fallbackCode.uppercased())
                                .font(.headline)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                locate()
                IumrahHaptics.soft()
            } label: {
                Group {
                    if locator.isLocating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "location.fill")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .frame(width: 42, height: 42)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("airport_title", settings.language))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .iumrahGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                     interactive: true, chrome: monochrome)
        .sheet(isPresented: $isPresented) {
            AirportPickerView(selection: $airport, fallbackCode: $fallbackCode)
        }
        .task {
            // The default TAS value is only a safe fallback. Until a concrete Airport
            // object exists, ask iOS once for location and resolve the nearest airport.
            if airport == nil { locate() }
        }
    }

    private func locate() {
        locator.locateNearestAirport { resolved in
            airport = resolved
            fallbackCode = resolved.iata.uppercased()
            IumrahHaptics.success()
        }
    }
}
