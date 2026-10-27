import SwiftUI

/// End-of-circuit confirmation. A touch must START on the handle and reach 94%
/// of available travel; interrupted gestures snap back without changing state.
struct UmrahTawafSwipeControl: View {
    let language: UmrahGuideLanguage
    let completed: Int
    let onComplete: () -> Void

    @State private var travel: CGFloat = 0
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let maxTravel = max(0, geometry.size.width - 62)
            let fraction = maxTravel > 0 ? travel / maxTravel : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.055))
                Capsule().fill(Color.black.opacity(0.09))
                    .frame(width: 54 + travel)
                HStack {
                    Spacer().frame(width: 63)
                    Text(UmrahTawafCopy.swipe(language))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.66))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 12)
                }
                Circle()
                    .fill(.black)
                    .frame(width: 54, height: 54)
                    .overlay {
                        Image(systemName: fraction > 0.90 ? "checkmark" : "chevron.right")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: travel + 4)
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        guard completed < 7 else { return }
                        if !dragging {
                            // Ignore swipes that begin outside the handle.
                            guard value.startLocation.x <= 72 else { return }
                            dragging = true
                        }
                        travel = max(0, min(maxTravel, value.location.x - 31))
                    }
                    .onEnded { _ in
                        guard dragging else { return }
                        let succeeded = maxTravel > 0 && travel >= maxTravel * 0.94
                        dragging = false
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.20)) {
                            travel = 0
                        }
                        if succeeded { onComplete() }
                    }
            )
        }
        .frame(height: 62)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UmrahTawafCopy.swipe(language))
        .accessibilityHint(UmrahTawafCopy.swipeHint(language))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { if completed < 7 { onComplete() } }
        .onChange(of: completed) { _, _ in
            dragging = false
            travel = 0
        }
    }
}

struct UmrahTawafProgressRing: View {
    let completed: Int
    let language: UmrahGuideLanguage

    var body: some View {
        ZStack {
            Circle().stroke(Color.black.opacity(0.09), lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(7, completed))) / 7)
                .stroke(.black, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.25), value: completed)
            VStack(spacing: 0) {
                Text("\(completed)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("/ 7")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.black)
        }
        .frame(width: 78, height: 78)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(UmrahTawafCopy.completed(language)) \(completed) / 7")
    }
}
