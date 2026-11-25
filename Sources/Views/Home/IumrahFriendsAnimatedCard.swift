import SwiftUI

/// Promotional illustration, never a representation of earned balance or issued coupons.
/// The existing Friends destination owns eligibility, invitations and real reward data.
struct IumrahFriendsAnimatedCard: View {
    let language: AppSettingsStore.Language

    private func copy(_ ru: String, _ en: String, _ uz: String, _ cy: String) -> String {
        IumrahFlightCopy.text(language, ru, en, uz, cy)
    }

    private var headline: String {
        copy("Приглашайте друзей. Получайте по $100.", "Invite friends. Earn $100 each.", "Har bir do‘st uchun $100", "Ҳар бир дўст учун $100")
    }

    private var terms: String {
        copy("Получайте бонус на баланс после подтверждённой оплаты первой подходящей поездки каждого приглашённого друга.",
             "Earn a balance reward after confirmed payment for each invited friend's first eligible trip.",
             "Har bir taklif qilingan do‘stning birinchi mos safari to‘lovi tasdiqlangach, balansingizga bonus oling.",
             "Ҳар бир таклиф қилинган дўстнинг биринчи мос сафари тўлови тасдиқлангач, балансингизга бонус олинг.")
    }

    private var actionTitle: String {
        copy("Пригласить друга", "Invite a friend", "Do‘stni taklif qilish", "Дўстни таклиф қилиш")
    }

    var body: some View {
        NavigationLink {
            IumrahFriendsVisualPage(language: language)
        } label: {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("iumrah FRIENDS")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.65))
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.09), in: Circle())
                        .overlay { Circle().strokeBorder(.white.opacity(0.13), lineWidth: 1) }
                }
                IumrahFriendsCouponArtwork()
                    .frame(height: 196)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 8) {
                    Text(headline)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(terms)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text(actionTitle)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(.subheadline, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.black)
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .frame(minHeight: 50)
                .background(.white, in: Capsule())
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.12), Color(white: 0.035), .black], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.11), lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(IumrahDashboardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("iumrah Friends. \(headline). \(terms)"))
        .accessibilityHint(Text(actionTitle))
        .accessibilityIdentifier("iumrah.friends.animatedCard")
    }
}

private struct IumrahFriendsCouponArtwork: View {
    @State private var startedAt = Date()
    @Environment(\.iumrahTabIsActive) private var activeTab
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, geometry.size.width / 292)
            IumrahDecorativeTimeline(maxFPS: 30, staticWhenConstrained: true) { date in
                let isStatic = date.timeIntervalSinceReferenceDate == 0
                let time = isStatic ? 4.0 : max(0, date.timeIntervalSince(startedAt))
                let phase = time
                ZStack {
                    IumrahFriendsRippleField(time: time)
                    ZStack {
                        coupon(index: 0, phase: phase)
                        coupon(index: 1, phase: phase)
                        coupon(index: 2, phase: phase)
                    }
                    .frame(width: 292, height: 180)
                    .scaleEffect(scale)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
        }
        .onAppear { startedAt = Date() }
        .onChange(of: activeTab) { _, active in if active { startedAt = Date() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { startedAt = Date() } }
    }

    private func smooth(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }

    private func coupon(index: Int, phase: Double) -> some View {
        let delay = Double(index) * 0.72
        // Three tickets arrive in sequence and remain visible once settled.
        let entry = smooth((phase - delay) / 1.0)
        let presence = entry
        let x: CGFloat = [-26, 27, 0][index]
        let y: CGFloat = [-37, -7, 27][index]
        let angle: Double = [-15, 13, -5][index]
        let drift = CGFloat(sin(phase * .pi / 5 + Double(index) * 0.65)) * 2.5
        return IumrahFriendsCoupon(index: index)
            .rotationEffect(.degrees(angle + (1 - presence) * 7))
            .rotation3DEffect(.degrees((1 - presence) * 13), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .scaleEffect(0.88 + 0.12 * presence)
            .offset(x: x + CGFloat(1 - presence) * 24, y: y + drift + CGFloat(1 - presence) * 27)
            .compositingGroup()
            .opacity(presence)
            .zIndex(Double(index))
    }
}

private struct IumrahFriendsRippleField: View {
    let time: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.48)
            let span = max(size.width, size.height) * 0.78
            // Native concentric, gently undulating waves; each ring fades at its edge.
            for i in 0..<7 {
                let p = (time / 7 + Double(i) / 7).truncatingRemainder(dividingBy: 1)
                let radius = 18 + CGFloat(p) * span
                var path = Path()
                for step in 0...96 {
                    let a = Double(step) / 96 * 2 * Double.pi
                    let ripple = CGFloat(sin(a * 3 + time * 0.6)) * 3.5 * CGFloat(sin(p * .pi))
                    let r = radius + ripple
                    let point = CGPoint(x: center.x + CGFloat(cos(a)) * r, y: center.y + CGFloat(sin(a)) * r * 0.73)
                    if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
                let alpha = 0.14 * pow(sin(p * .pi), 1.3)
                context.stroke(path, with: .color(Color(white: 0.85).opacity(alpha)), lineWidth: 0.8)
            }
        }
        .background {
            RadialGradient(colors: [.white.opacity(0.11), .clear], center: .center, startRadius: 8, endRadius: 145)
        }
    }
}

private struct IumrahFriendsCoupon: View {
    let index: Int

    private var ink: Color { index == 2 ? Color(white: 0.10) : .white }
    private var shades: [Color] {
        switch index {
        case 0: return [Color(white: 0.35), Color(white: 0.16)]
        case 1: return [Color(white: 0.60), Color(white: 0.32)]
        default: return [Color(white: 0.99), Color(white: 0.71), Color(white: 0.94)]
        }
    }
    var body: some View {
        ZStack {
            let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
            shape.fill(LinearGradient(colors: shades, startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.65), .white.opacity(0.08), .white.opacity(0.30)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("$100")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .tracking(-1)
                        .monospacedDigit()
                    Spacer(minLength: 1)
                    Text("iumrah FRIENDS")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(ink.opacity(0.72))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle()
                    .fill(ink.opacity(0.18))
                    .frame(width: 1)
                    .padding(.vertical, 3)
                Image(systemName: "gift")
                    .font(.system(size: 19, weight: .light))
                    .frame(width: 38)
            }
            .foregroundStyle(ink)
            .padding(12)
        }
        .frame(width: 168, height: 83)
        .shadow(color: .black.opacity(0.52), radius: 9, x: 0, y: 5)
    }
}
