import AVFoundation
import Combine
import Foundation

/// Playback is screen-scoped. Every navigation/language change invalidates the
/// pending request, so an earlier download cannot start narration on a new step.
@MainActor
final class UmrahFlowAudioService: ObservableObject {
    @Published private(set) var currentKey: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var isUsingSystemVoice = false
    @Published private(set) var lastError: String?
    @Published private(set) var amplitude: Double = 0

    private var player: AVAudioPlayer?
    private var meterTimer: Timer?
    private var loadTask: Task<Void, Never>?
    private var activeRequestID = UUID()
    private var peakHold: Double = 0
    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private let speechDelegate = UmrahFlowSpeechDelegate()
    private var interruptionObserver: NSObjectProtocol?

    private let audioCache: NSCache<NSURL, NSData> = {
        let cache = NSCache<NSURL, NSData>()
        cache.totalCostLimit = 48 * 1024 * 1024
        cache.countLimit = 18
        return cache
    }()

    init() {
        speechDelegate.didFinish = { [weak self] utterance in
            Task { @MainActor [weak self] in
                guard let self, self.isUsingSystemVoice,
                      self.currentUtterance === utterance else { return }
                self.finishPlayback(clearKey: false)
            }
        }
        synthesizer.delegate = speechDelegate
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let kind = AVAudioSession.InterruptionType(rawValue: raw), kind == .began else { return }
            Task { @MainActor [weak self] in self?.stop() }
        }
    }

    /// A published recording is preferred. If it cannot be downloaded, the exact
    /// displayed and reviewed guide text can be spoken by an installed iOS voice.
    /// No language is substituted silently if iOS lacks that voice.
    func toggle(key: String, url: URL?, fallbackSpeechText: String? = nil, language: UmrahGuideLanguage = .english) {
        if currentKey == key && (isPlaying || isLoading) {
            stop()
            return
        }
        play(key: key, url: url, fallbackSpeechText: fallbackSpeechText, language: language)
    }

    func play(key: String, url: URL?, fallbackSpeechText: String? = nil, language: UmrahGuideLanguage = .english) {
        stop()
        let requestID = UUID()
        activeRequestID = requestID
        currentKey = key
        lastError = nil
        amplitude = 0

        guard let url else {
            startSystemSpeech(text: fallbackSpeechText, language: language)
            return
        }

        isLoading = true
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await self.audioData(for: url)
                try Task.checkCancellation()
                guard self.activeRequestID == requestID else { return }
                try self.beginPlayback(data: data)
            } catch is CancellationError {
                // Navigation, a replacement clip or a manual stop cancelled this load.
            } catch {
                guard self.activeRequestID == requestID else { return }
                self.isLoading = false
                self.startSystemSpeech(text: fallbackSpeechText, language: language)
                if !self.isPlaying {
                    self.lastError = UmrahFlowCopy.audioUnavailable(language)
                }
            }
        }
    }

    func stop() {
        activeRequestID = UUID()
        loadTask?.cancel()
        loadTask = nil
        player?.stop()
        player = nil
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        stopMetering()
        deactivateSession()
        isPlaying = false
        isLoading = false
        isUsingSystemVoice = false
        amplitude = 0
        peakHold = 0
        currentKey = nil
        lastError = nil
    }

    /// An invalid/HTML error response must never be cached as an MP3.
    private func audioData(for url: URL) async throws -> Data {
        let cacheKey = url as NSURL
        if let cached = audioCache.object(forKey: cacheKey) { return cached as Data }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard !data.isEmpty, data.count < 30 * 1024 * 1024 else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        // Supabase Storage may return an HTML/JSON error page with HTTP 200.
        let prefix = data.prefix(64)
        if prefix.first == 0x3C || prefix.first == 0x7B {
            throw URLError(.cannotDecodeContentData)
        }
        audioCache.setObject(data as NSData, forKey: cacheKey, cost: data.count)
        return data
    }

    private func beginPlayback(data: Data) throws {
        try activateSession()
        let player = try AVAudioPlayer(data: data)
        player.isMeteringEnabled = true
        player.prepareToPlay()
        guard player.play() else { throw URLError(.cannotOpenFile) }
        self.player = player
        isUsingSystemVoice = false
        isLoading = false
        isPlaying = true
        startMetering()
    }

    private func startSystemSpeech(text: String?, language: UmrahGuideLanguage) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            isLoading = false
            lastError = UmrahFlowCopy.audioUnavailable(language)
            return
        }
        guard let voice = AVSpeechSynthesisVoice(language: language.localeIdentifier) else {
            isLoading = false
            lastError = UmrahFlowCopy.audioUnavailable(language)
            return
        }
        do {
            try activateSession()
            let utterance = AVSpeechUtterance(string: trimmed)
            utterance.voice = voice
            utterance.rate = 0.47
            utterance.postUtteranceDelay = 0
            currentUtterance = utterance
            isUsingSystemVoice = true
            isPlaying = true
            isLoading = false
            synthesizer.speak(utterance)
        } catch {
            isPlaying = false
            isLoading = false
            isUsingSystemVoice = false
            lastError = UmrahFlowCopy.audioUnavailable(language)
        }
    }

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay])
        try session.setActive(true)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startMetering() {
        stopMetering()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateAmplitudeMeter() }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func updateAmplitudeMeter() {
        guard let player else { amplitude = 0; return }
        guard player.isPlaying else {
            if isPlaying { finishPlayback(clearKey: false) }
            return
        }
        player.updateMeters()
        var averageDB: Float = -80
        var peakDB: Float = -80
        for channel in 0..<max(player.numberOfChannels, 1) {
            averageDB = max(averageDB, player.averagePower(forChannel: channel))
            peakDB = max(peakDB, player.peakPower(forChannel: channel))
        }
        let average = normalizedPower(averageDB, floor: -56)
        let peak = normalizedPower(peakDB, floor: -48)
        var target = min(1.0, max(average * 0.92, peak * 0.86) * 1.20)
        peakHold = max(target, peakHold * 0.80)
        target = max(target, peakHold * 0.92)
        if target < 0.018 { target = 0 }
        let smoothing = target > amplitude ? 0.80 : 0.17
        amplitude += (target - amplitude) * smoothing
        if amplitude < 0.002 { amplitude = 0 }
    }

    private func normalizedPower(_ decibels: Float, floor: Float) -> Double {
        let clamped = max(floor, min(0, decibels))
        return pow(max(0, min(1, Double((clamped - floor) / -floor))), 0.66)
    }

    private func finishPlayback(clearKey: Bool) {
        stopMetering()
        player = nil
        currentUtterance = nil
        deactivateSession()
        loadTask = nil
        isPlaying = false
        isLoading = false
        isUsingSystemVoice = false
        amplitude = 0
        peakHold = 0
        if clearKey { currentKey = nil }
    }

    deinit {
        meterTimer?.invalidate()
        loadTask?.cancel()
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }
}

/// NSObject adapter keeps AVFoundation delegate callbacks isolated from the
/// observable UI object. The service checks the active playback mode before reset.
private final class UmrahFlowSpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var didFinish: ((AVSpeechUtterance) -> Void)?
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        didFinish?(utterance)
    }
}
