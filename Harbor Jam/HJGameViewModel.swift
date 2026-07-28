import Foundation
import SwiftUI
import AudioToolbox
import UIKit

enum HJGameMode: Equatable {
    case campaign(chapter: Int, level: Int)
    case daily(dayKey: Int)
}

final class HJGameViewModel: ObservableObject {
    let mode: HJGameMode
    let par: Int
    let initialState: HJBoardState

    @Published var state: HJBoardState
    @Published var won = false
    @Published var earnedStars = 0
    @Published var shakeBoatID: Int? = nil
    @Published var lastExitedBoatID: Int? = nil
    @Published var tugArmed = false

    private var undoStack: [HJBoardState] = []
    private(set) var undosUsed = 0
    private(set) var tugsUsed = 0
    private var soundOn: Bool
    private var hapticsOn: Bool

    init?(mode: HJGameMode, store: HJStore) {
        self.mode = mode
        let generated: HJGeneratedLevel?
        switch mode {
        case .campaign(let chapter, let level):
            generated = HJGenerator.campaignLevel(chapter: chapter, level: level)
        case .daily(let dayKey):
            generated = HJGenerator.dailyLevel(dayKey: dayKey)
        }
        guard let g = generated else { return nil }
        par = g.par
        initialState = g.start
        state = g.start
        soundOn = store.save.soundOn
        hapticsOn = store.save.hapticsOn
    }

    var boatsRemaining: Int { state.boats.count }
    var totalBoats: Int { par }
    var canUndo: Bool { !undoStack.isEmpty && !won }

    func tapBoat(_ id: Int, store: HJStore) {
        guard !won else { return }
        if tugArmed {
            let before = state
            if HJEngine.tugRotate(boatID: id, state: &state) {
                undoStack.append(before)
                tugsUsed += 1
                haptic(.light)
                playSound(1104)
            } else {
                shake(id)
            }
            tugArmed = false
            return
        }
        let before = state
        let outcome = HJEngine.tap(boatID: id, state: &state)
        switch outcome {
        case .exited(let boatID):
            undoStack.append(before)
            lastExitedBoatID = boatID
            haptic(.medium)
            playSound(1057)
            if state.isCleared {
                finish(store: store)
            }
        case .moved:
            undoStack.append(before)
            haptic(.light)
            playSound(1104)
        case .blocked, .anchored:
            // A refused tap still spends a tick, so the board changed and the state
            // belongs on the undo stack like any other move.
            undoStack.append(before)
            shake(id)
            haptic(.heavy)
        case .invalid:
            break
        }
    }

    func undo() {
        guard let prev = undoStack.popLast(), !won else { return }
        state = prev
        undosUsed += 1
    }

    func restart() {
        guard !won else { return }
        if state != initialState {
            undoStack.append(state)
            undosUsed += 1
        }
        state = initialState
        tugArmed = false
    }

    private func finish(store: HJStore) {
        won = true
        haptic(.medium)
        playSound(1025)
        switch mode {
        case .campaign(let chapter, let level):
            earnedStars = store.reportCampaignWin(chapter: chapter, level: level,
                                                  taps: state.taps, par: par,
                                                  usedUndo: undosUsed > 0,
                                                  boatsExited: totalBoats,
                                                  tugsUsed: tugsUsed, undos: undosUsed)
        case .daily(let dayKey):
            earnedStars = state.taps <= par ? 3 : (state.taps <= par + 2 ? 2 : 1)
            store.reportDailyWin(dayKey: dayKey, taps: state.taps,
                                 usedUndo: undosUsed > 0,
                                 boatsExited: totalBoats,
                                 tugsUsed: tugsUsed, undos: undosUsed)
        }
    }

    private func shake(_ id: Int) {
        shakeBoatID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            if self?.shakeBoatID == id { self?.shakeBoatID = nil }
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard hapticsOn else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func playSound(_ id: SystemSoundID) {
        guard soundOn else { return }
        AudioServicesPlaySystemSound(id)
    }
}
