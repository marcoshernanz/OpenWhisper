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

private func checkTime(of action: FunctionKeyDictationGesture.Action) -> TimeInterval? {
    guard case .waitForSecondTap(let checkTime) = action else { return nil }
    return checkTime
}

@Test func pendingTapFinishesWhenCheckedOnTime() {
    var gesture = FunctionKeyDictationGesture(maximumTapDuration: 0.25, doubleTapInterval: 0.25)

    #expect(gesture.keyDown(at: 1.0) == .startRecording)
    #expect(checkTime(of: gesture.keyUp(at: 1.125)) == 1.375)
    #expect(checkTime(of: gesture.checkPendingTap(at: 1.25, scheduledFor: 1.375)) == 1.375)
    #expect(gesture.checkPendingTap(at: 1.4, scheduledFor: 1.375) == .finishRecording)
    #expect(gesture.keyDown(at: 1.5) == .startRecording)
}

/// Starting a recording can keep the app too busy to handle fn for a while. Key events still carry when
/// fn moved, but the check for a second tap may come due before the second press is handled.
@Test func doubleTapLocksRecordingWhenTheAppHandlesItLate() {
    var gesture = FunctionKeyDictationGesture(maximumTapDuration: 0.25, doubleTapInterval: 0.25)

    // The app handles the first press, then is busy until 2.0 while fn is tapped twice.
    #expect(gesture.keyDown(at: 1.0) == .startRecording)
    #expect(checkTime(of: gesture.keyUp(at: 1.125)) == 1.375)
    #expect(checkTime(of: gesture.checkPendingTap(at: 2.0, scheduledFor: 1.375)) != nil)

    #expect(gesture.expirePendingTap(at: 1.25) == .none)
    #expect(gesture.keyDown(at: 1.25) == .lockRecording)
    #expect(gesture.keyUp(at: 1.375) == .none)
    #expect(gesture.checkPendingTap(at: 2.05, scheduledFor: 2.05) == .none)
    #expect(gesture.keyDown(at: 4.0) == .finishRecording)
}

@Test func lateCheckFinishesATapOnceChecksRunOnTime() {
    var gesture = FunctionKeyDictationGesture(maximumTapDuration: 0.25, doubleTapInterval: 0.25)

    #expect(gesture.keyDown(at: 1.0) == .startRecording)
    _ = gesture.keyUp(at: 1.125)

    guard let recheck = checkTime(of: gesture.checkPendingTap(at: 2.0, scheduledFor: 1.375)) else {
        Issue.record("Expected a late check to look again")
        return
    }

    #expect(recheck > 2.0 && recheck < 2.2)
    #expect(gesture.checkPendingTap(at: recheck, scheduledFor: recheck) == .finishRecording)
}

@Test func pendingTapStopsWaitingForKeyEventsAfterAFewSeconds() {
    var gesture = FunctionKeyDictationGesture(maximumTapDuration: 0.25, doubleTapInterval: 0.25)

    #expect(gesture.keyDown(at: 1.0) == .startRecording)
    _ = gesture.keyUp(at: 1.125)

    #expect(gesture.checkPendingTap(at: 5.0, scheduledFor: 4.0) == .finishRecording)
}
