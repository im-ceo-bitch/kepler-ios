import Foundation
import SwiftUI

@MainActor
final class UmrahFlowState: ObservableObject {
    enum Stage: Int, CaseIterable, Hashable {
        case inUmrah
        case start
        case tawaf
        case postTawaf
        case safa
        case end
        case afterUmrah
    }

    enum RitualMode: String, CaseIterable, Hashable {
        case listening
        case reading
    }

    @Published var stage: Stage
    @Published var startPhase = 0

    @Published var tawafRound = 1
    // A round is counted only after an explicit swipe, never by paging instructions.
    @Published private(set) var tawafIsComplete = false
    @Published var tawafTextMode = 0
    @Published var tawafMode: RitualMode = .listening
    @Published var tawafReadingStep = 0
    @Published var tawafZikrCount = 0

    @Published var postTawafStep = 0

    @Published var safaRound = 1
    @Published var safaTextMode = 0
    @Published var safaMode: RitualMode = .listening
    @Published var safaReadingStep = 0

    @Published var endPhase = 0

    init(initialStage: Stage = .start) {
        self.stage = initialStage
    }

    var tawafCompletedRounds: Int {
        tawafIsComplete ? 7 : max(0, min(6, tawafRound - 1))
    }

    var currentTawafRound: Int { min(7, max(1, tawafRound)) }

    /// The route has five guided ritual phases; this is a milestone estimate,
    /// not a sensor-derived measurement of the pilgrim's physical progress.
    var routeStageNumber: Int {
        switch stage {
        case .inUmrah: return 0
        case .start: return 1
        case .tawaf: return 2
        case .postTawaf: return 3
        case .safa: return 4
        case .end, .afterUmrah: return 5
        }
    }

    var topProgress: Double {
        switch stage {
        case .inUmrah:
            return 0
        case .start:
            return (Double(startPhase) / 4.0) * 0.20
        case .tawaf:
            return 0.20 + (Double(tawafCompletedRounds) / 7.0) * 0.20
        case .postTawaf:
            return 0.40 + (Double(postTawafStep) / 4.0) * 0.20
        case .safa:
            return 0.60 + (Double(safaRound - 1) / 7.0) * 0.20
        case .end:
            return 0.80 + (Double(endPhase) / 3.0) * 0.20
        case .afterUmrah:
            return 1
        }
    }

    // A ritual is long-running: leaving the screen or having iOS terminate the
    // process must not silently lose Tawaf / Sa'i round counters.
    // Resumption is opt-in in UmrahFlowRootView, never automatic.
    private static let checkpointKey = "iumrah.umrahFlow.progress.v2"

    private struct Checkpoint: Codable {
        let savedAt: Date
        let stage: Int
        let startPhase: Int
        let tawafRound: Int
        // Optional to retain compatibility with progress.v2 checkpoints.
        let tawafIsComplete: Bool?
        let tawafTextMode: Int
        let tawafMode: String
        let tawafReadingStep: Int
        let tawafZikrCount: Int
        let postTawafStep: Int
        let safaRound: Int
        let safaTextMode: Int
        let safaMode: String
        let safaReadingStep: Int
        let endPhase: Int
    }

    static var hasSavedProgress: Bool {
        guard let checkpoint = decodedCheckpoint() else { return false }
        return checkpoint.stage != Stage.afterUmrah.rawValue &&
            checkpoint.stage != Stage.inUmrah.rawValue
    }

    private static func decodedCheckpoint() -> Checkpoint? {
        guard let data = UserDefaults.standard.data(forKey: checkpointKey),
              let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: data),
              Date().timeIntervalSince(checkpoint.savedAt) < 60 * 24 * 60 * 60,
              checkpoint.savedAt.timeIntervalSinceNow < 60,
              Stage(rawValue: checkpoint.stage) != nil else { return nil }
        return checkpoint
    }

    func saveCheckpoint() {
        guard stage != .afterUmrah && stage != .inUmrah else {
            Self.discardCheckpoint()
            return
        }
        let checkpoint = Checkpoint(
            savedAt: Date(), stage: stage.rawValue, startPhase: startPhase,
            tawafRound: tawafRound, tawafIsComplete: tawafIsComplete,
            tawafTextMode: tawafTextMode,
            tawafMode: tawafMode.rawValue, tawafReadingStep: tawafReadingStep,
            tawafZikrCount: tawafZikrCount, postTawafStep: postTawafStep,
            safaRound: safaRound, safaTextMode: safaTextMode,
            safaMode: safaMode.rawValue, safaReadingStep: safaReadingStep,
            endPhase: endPhase
        )
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        UserDefaults.standard.set(data, forKey: Self.checkpointKey)
    }

    func restoreCheckpoint() {
        guard let saved = Self.decodedCheckpoint(), let restoredStage = Stage(rawValue: saved.stage),
              restoredStage != .afterUmrah, restoredStage != .inUmrah else { return }
        startPhase = min(3, max(0, saved.startPhase))
        tawafRound = min(7, max(1, saved.tawafRound))
        tawafIsComplete = saved.tawafIsComplete ?? (restoredStage.rawValue > Stage.tawaf.rawValue)
        tawafTextMode = min(2, max(0, saved.tawafTextMode))
        tawafMode = RitualMode(rawValue: saved.tawafMode) ?? .listening
        tawafReadingStep = min(6, max(0, saved.tawafReadingStep))
        tawafZikrCount = min(20, max(0, saved.tawafZikrCount))
        postTawafStep = min(3, max(0, saved.postTawafStep))
        safaRound = min(7, max(1, saved.safaRound))
        safaTextMode = min(2, max(0, saved.safaTextMode))
        safaMode = RitualMode(rawValue: saved.safaMode) ?? .listening
        safaReadingStep = min(6, max(0, saved.safaReadingStep))
        endPhase = min(2, max(0, saved.endPhase))
        stage = restoredStage
    }

    static func discardCheckpoint() {
        UserDefaults.standard.removeObject(forKey: checkpointKey)
    }

    @discardableResult
    func completeTawafRound() -> Bool {
        guard stage == .tawaf, !tawafIsComplete else { return false }
        if tawafRound < 7 {
            tawafRound += 1
        } else {
            tawafIsComplete = true
        }
        tawafTextMode = 0
        resetTawafReading()
        saveCheckpoint()
        return true
    }

    @discardableResult
    func undoLastTawafRound() -> Bool {
        guard stage == .tawaf, tawafCompletedRounds > 0 else { return false }
        if tawafIsComplete {
            tawafIsComplete = false
        } else {
            tawafRound = max(1, tawafRound - 1)
        }
        tawafTextMode = 0
        resetTawafReading()
        saveCheckpoint()
        return true
    }

    func resetTawafReading() {
        tawafReadingStep = 0
        tawafZikrCount = 0
    }

    func resetSafaReading() {
        safaReadingStep = 0
    }

    func reset() {
        startPhase = 0
        tawafRound = 1
        tawafIsComplete = false
        tawafTextMode = 0
        tawafMode = .listening
        resetTawafReading()
        postTawafStep = 0
        safaRound = 1
        safaTextMode = 0
        safaMode = .listening
        resetSafaReading()
        endPhase = 0
        stage = .start
    }
}

enum UmrahFlowKeys {
    static let all: Set<String> = {
        var keys: Set<String> = [
            "complete_btn", "continue_btn", "tap_btn", "sunna_dua_btn",
            "start_text", "start_text1", "start_text2", "start_text3",
            "end_text", "end_text1", "end_text3",
            "home1_title", "home1_sub", "home1_btn", "home1_btn3_sub",
            "home2_3title", "home2_3_subtitle", "home_3_btn", "home_3_btn_sub",
            "home_3_btn2", "home_3_btn2_sub", "home_3_btn3",
            "tawaf_title", "tawaf_break_title", "tawafpray_title1", "tawafpray_text1",
            "tawaf_common_text1", "tawaf_common_text2", "tawaf_common_text3", "tawaf_common_text4",
            "zamzam_title", "zamzam_title1", "zamzam_text",
            "safago_title", "safago_title1", "safago_text", "safadua_title",
            "overlay_safa_title", "overlay_safa_text1",
            "umrah_start_title", "sai_title", "tahallul_title",
            "navigate_button", "close_button", "cancel_omra"
        ]

        for round in 1...7 {
            keys.insert("tawaf\(round)_text1")
            keys.insert("tawaf\(round)_text2")
            keys.insert("tawaf\(round)_tarab1")
            keys.insert("tawaf\(round)_zikr_text")
            keys.insert("tawaf\(round)_zikr_repeat")
            for arabicIndex in 1...3 {
                keys.insert("tawaf\(round)_reading_arab\(arabicIndex)")
            }
            for textIndex in 1...6 {
                keys.insert("tawaf\(round)_reading_text\(textIndex)")
            }

            keys.insert("safa\(round)_title1")
            keys.insert("safa\(round)_text1")
            keys.insert("safa\(round)_text2")
            keys.insert("safa\(round)_sarab1")
        }
        return keys
    }()
}
