import Foundation
import Testing
@testable import OpenWhisperCore

@Test func holdStartsImmediatelyAndFinishesOnRelease() {
    var gesture = FunctionKeyDictationGesture(
        maximumTapDuration: 0.25,
        doubleTapInterval: 0.3
    )

    #expect(gesture.keyDown(at: 1.0) == .startRecording)
    #expect(gesture.keyUp(at: 1.5) == .finishRecording)
}

@Test func shortTapWaitsForSecondTapBeforeFinishing() {
    var gesture = FunctionKeyDictationGesture(
        maximumTapDuration: 0.25,
        doubleTapInterval: 0.3
    )

    #expect(gesture.keyDown(at: 1.0) == .startRecording)
    let action = gesture.keyUp(at: 1.1)

    guard case .waitForSecondTap(let deadline) = action else {
        Issue.record("Expected a pending double-tap window")
        return
    }

    #expect(abs(deadline - 1.4) < 0.0001)
    #expect(gesture.expirePendingTap(at: deadline - 0.01) == .none)
    #expect(gesture.expirePendingTap(at: deadline) == .finishRecording)
}

@Test func doubleTapLocksRecordingUntilNextFunctionKeyPress() {
    var gesture = FunctionKeyDictationGesture(
        maximumTapDuration: 0.25,
        doubleTapInterval: 0.3
    )

    #expect(gesture.keyDown(at: 1.0) == .startRecording)
    guard case .waitForSecondTap = gesture.keyUp(at: 1.1) else {
        Issue.record("Expected a pending double-tap window")
        return
    }

    #expect(gesture.keyDown(at: 1.22) == .lockRecording)
    #expect(gesture.keyUp(at: 1.26) == .none)
    #expect(gesture.keyDown(at: 2.0) == .finishRecording)
    #expect(gesture.keyUp(at: 2.05) == .none)
}

@Test func stalePendingTapCanExpireBeforeANewPressStartsRecording() {
    var gesture = FunctionKeyDictationGesture(
        maximumTapDuration: 0.25,
        doubleTapInterval: 0.3
    )

    #expect(gesture.keyDown(at: 1.0) == .startRecording)
    guard case .waitForSecondTap = gesture.keyUp(at: 1.1) else {
        Issue.record("Expected a pending double-tap window")
        return
    }

    #expect(gesture.expirePendingTap(at: 1.41) == .finishRecording)
    #expect(gesture.keyDown(at: 1.42) == .startRecording)
    #expect(gesture.keyUp(at: 1.9) == .finishRecording)
}
