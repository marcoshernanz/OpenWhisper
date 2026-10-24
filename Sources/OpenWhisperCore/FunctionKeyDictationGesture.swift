import Foundation

public struct FunctionKeyDictationGesture: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        case none
        case startRecording
        case finishRecording
        /// Check at `checkAt` whether a second tap came, with `checkPendingTap`.
        case waitForSecondTap(checkAt: TimeInterval)
        case lockRecording
    }

    private enum State: Sendable, Equatable {
        case idle
        case pressing(startedAt: TimeInterval)
        case waitingForSecondTap(deadline: TimeInterval)
        case locked
        case ignoringReleaseAfterLockedStop
    }

    public let maximumTapDuration: TimeInterval
    public let doubleTapInterval: TimeInterval
    private var state: State = .idle

    public init(
        maximumTapDuration: TimeInterval = 0.28,
        doubleTapInterval: TimeInterval = 0.34
    ) {
        self.maximumTapDuration = max(0.05, maximumTapDuration)
        self.doubleTapInterval = max(0.1, doubleTapInterval)
    }

    public mutating func keyDown(at timestamp: TimeInterval) -> Action {
        switch state {
        case .idle:
            state = .pressing(startedAt: timestamp)
            return .startRecording
        case .pressing:
            return .none
        case .waitingForSecondTap(let deadline):
            guard timestamp <= deadline else {
                state = .pressing(startedAt: timestamp)
                return .startRecording
            }

            state = .locked
            return .lockRecording
        case .locked:
            state = .ignoringReleaseAfterLockedStop
            return .finishRecording
        case .ignoringReleaseAfterLockedStop:
            return .none
        }
    }

    public mutating func keyUp(at timestamp: TimeInterval) -> Action {
        switch state {
        case .idle:
            return .none
        case .pressing(let startedAt):
            let pressDuration = max(0, timestamp - startedAt)
            guard pressDuration <= maximumTapDuration else {
                state = .idle
                return .finishRecording
            }

            let deadline = timestamp + doubleTapInterval
            state = .waitingForSecondTap(deadline: deadline)
            return .waitForSecondTap(checkAt: deadline)
        case .waitingForSecondTap:
            return .none
        case .locked:
            return .none
        case .ignoringReleaseAfterLockedStop:
            state = .idle
            return .none
        }
    }

    /// Ends a tap that no second tap followed, for a key event at `timestamp` after its deadline.
    public mutating func expirePendingTap(at timestamp: TimeInterval) -> Action {
        guard case .waitingForSecondTap(let deadline) = state,
              timestamp >= deadline
        else {
            return .none
        }

        state = .idle
        return .finishRecording
    }

    /// Ends a tap that no second tap followed, from a check that was due at `scheduledTime`.
    ///
    /// A check that runs late means the app was too busy to handle key events, so a second tap made in
    /// time may still be waiting to be handled. The check is then made again shortly instead, until one
    /// runs on time or a few seconds have passed.
    public mutating func checkPendingTap(
        at timestamp: TimeInterval,
        scheduledFor scheduledTime: TimeInterval
    ) -> Action {
        guard case .waitingForSecondTap(let deadline) = state else {
            return .none
        }

        guard timestamp >= deadline else {
            return .waitForSecondTap(checkAt: deadline)
        }

        let isLate = timestamp - scheduledTime > Self.lateCheckTolerance
        if isLate, timestamp - deadline < Self.longestKeyEventDelay {
            return .waitForSecondTap(checkAt: timestamp + Self.recheckInterval)
        }

        state = .idle
        return .finishRecording
    }

    public mutating func cancel() {
        state = .idle
    }

    private static let lateCheckTolerance: TimeInterval = 0.05
    private static let recheckInterval: TimeInterval = 0.05
    private static let longestKeyEventDelay: TimeInterval = 3
}
