import SwiftUI

struct SectionHeader: View {
    let eyebrow: String?
    let title: String
    let subtitle: String?

    init(_ title: String, eyebrow: String? = nil, subtitle: String? = nil) {
        self.title = title
        self.eyebrow = eyebrow
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(IumrahType.bold(12, relativeTo: .caption))
                    .foregroundStyle(Color.iumrahMuted)
                    .tracking(0.7)
            }
            Text(title)
                .font(IumrahType.sectionTitle)
                .tracking(-0.7)
            if let subtitle {
                Text(subtitle)
                    .font(IumrahType.secondary)
                    .foregroundStyle(Color.iumrahMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
