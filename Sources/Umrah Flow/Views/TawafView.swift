import SwiftUI

/// Ritual guidance and physical circuit counting have independent navigation.
/// Pages can be revisited freely; only a deliberate swipe records a circuit.
struct TawafView: View {
    @ObservedObject var flow: UmrahFlowState
    @ObservedObject var store: UmrahFlowStore
    @ObservedObject var audio: UmrahFlowAudioService
    let showsModeBar: Bool // Legacy call-site compatibility; no duplicated mode bar.

    @State private var showsSunnahDua = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var language: UmrahGuideLanguage { store.guideLanguage }
    private var audioKey: String { "tawaf_\(flow.currentTawafRound)" }
    private var isCurrentPlaying: Bool { audio.currentKey == audioKey && audio.isPlaying }
    private var isCurrentLoading: Bool { audio.currentKey == audioKey && audio.isLoading }
    private var primary: Color { colorScheme == .dark ? .white : .black }

    var body: some View {
        VStack(spacing: 0) {
            if flow.tawafMode == .reading {
                readingContent
            } else {
                guidanceContent
            }

            swipeCard
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: flow.tawafMode)
        .sheet(isPresented: $showsSunnahDua) {
            SunnahDuaSheet(store: store)
        }
    }

    private var guidanceContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                UmrahTawafOrbitHero(completed: flow.tawafCompletedRounds, language: language)

                HStack(spacing: 9) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .medium))
                    Text(UmrahTawafCopy.direction(language))
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(primary.opacity(0.65))
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    Text(UmrahTawafCopy.guidance(language))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(primary.opacity(0.65))

                    Text(activeText)
                        .font(.system(size: flow.tawafTextMode == 2 ? 21 : 18, weight: .medium))
                        .foregroundStyle(primary)
                        .multilineTextAlignment(flow.tawafTextMode == 2 ? .trailing : .leading)
                        .environment(\.layoutDirection, flow.tawafTextMode == 2 ? .rightToLeft : .leftToRight)
                        .fixedSize(horizontal: false, vertical: true)
                        .id("\(flow.tawafRound)-\(flow.tawafTextMode)")

                    Button {
                        IumrahHaptics.selection()
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                            flow.tawafTextMode = (flow.tawafTextMode + 1) % 3
                        }
                    } label: {
                        Label(UmrahTawafCopy.otherText(language), systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(primary.opacity(0.68))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 3)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(primary.opacity(colorScheme == .dark ? 0.07 : 0.045), in: RoundedRectangle(cornerRadius: 22))

                HStack(spacing: 10) {
                    Button {
                        IumrahHaptics.soft()
                        if isCurrentPlaying || isCurrentLoading { audio.stop() }
                        else {
                            audio.toggle(
                                key: audioKey,
                                url: store.audioURL(for: audioKey),
                                fallbackSpeechText: activeText,
                                language: language
                            )
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isCurrentLoading { ProgressView().controlSize(.small) }
                            else { Image(systemName: isCurrentPlaying ? "pause.fill" : "play.fill") }
                            Text(isCurrentPlaying ? UmrahTawafCopy.pause(language) : isCurrentLoading ? UmrahFlowCopy.loadingVoice(language) : UmrahTawafCopy.play(language))
                                .lineLimit(1)
                                .minimumScaleFactor(0.80)
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(primary.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("umrahFlow.tawaf.audio")

                    Button {
                        audio.stop()
                        flow.tawafMode = .reading
                    } label: {
                        Label(UmrahTawafCopy.read(language), systemImage: "book.closed")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(primary.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    audio.stop()
                    showsSunnahDua = true
                } label: {
                    Label(store.text("sunna_dua_btn", fallback: "Sunnah Dua"), systemImage: "hands.sparkles")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                if audio.currentKey == audioKey, let error = audio.lastError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var readingContent: some View {
        VStack(spacing: 4) {
            HStack {
                Button {
                    flow.tawafMode = .listening
                } label: {
                    Label(UmrahTawafCopy.backToGuide(language), systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(primary)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("\(UmrahTawafCopy.round(language)) \(flow.tawafRound)/7")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            TawafReadingPage(flow: flow, store: store)
        }
    }

    private var swipeCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if flow.tawafIsComplete {
                    Button {
                        audio.stop()
                        IumrahHaptics.selection()
                        flow.stage = .postTawaf
                        flow.saveCheckpoint()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text(UmrahTawafCopy.next(language))
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 62)
                        .background(.black, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    UmrahTawafSwipeControl(language: language, completed: flow.tawafCompletedRounds) {
                        audio.stop()
                        IumrahHaptics.selection()
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                            _ = flow.completeTawafRound()
                        }
                    }
                }

                UmrahTawafProgressRing(completed: flow.tawafCompletedRounds, language: language)
                    .frame(width: 78, height: 78)
            }

            HStack {
                Text(flow.tawafIsComplete ? UmrahTawafCopy.done(language) : UmrahTawafCopy.swipeHint(language))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if flow.tawafCompletedRounds > 0 {
                    Button {
                        audio.stop()
                        IumrahHaptics.selection()
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                            _ = flow.undoLastTawafRound()
                        }
                    } label: {
                        Label(UmrahTawafCopy.undo(language), systemImage: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("umrahFlow.tawaf.undo")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .background(colorScheme == .dark ? Color.black : Color(red: 0.975, green: 0.975, blue: 0.975))
        .accessibilityIdentifier("umrahFlow.tawaf.completion")
    }

    private var activeText: String {
        let round = flow.currentTawafRound
        switch flow.tawafTextMode {
        case 0:
            return store.text("tawaf\(round)_text1", fallback: "Continue Tawaf calmly and keep your attention on worship.")
        case 1:
            return store.text("tawaf\(round)_text2", fallback: store.text("tawaf\(round)_text1", fallback: "Make dua while continuing this circuit."))
        default:
            return store.text("tawaf\(round)_tarab1", fallback: store.text("tawaf\(round)_text2", fallback: "Make dua while continuing this circuit."))
        }
    }
}
