import SwiftUI

struct CounterRow: View {
    let title: String
    let subtitle: String?
    @Binding var value: Int
    let minimum: Int
    let maximum: Int

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(IumrahType.bold(16, relativeTo: .body))
                if let subtitle {
                    Text(subtitle).font(IumrahType.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 14) {
                Button {
                    value = max(minimum, value - 1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .iumrahGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .disabled(value <= minimum)

                Text("\(value)")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 22)

                Button {
                    value = min(maximum, value + 1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .iumrahGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .disabled(value >= maximum)
            }
        }
        .padding(.vertical, 6)
    }
}
