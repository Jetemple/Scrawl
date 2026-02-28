import Foundation

public struct HotkeyGestureConfig: Sendable {
    public var holdThreshold: TimeInterval
    public var doubleTapGap: TimeInterval

    public init(
        holdThreshold: TimeInterval = 0.18,
        doubleTapGap: TimeInterval = 0.30
    ) {
        self.holdThreshold = holdThreshold
        self.doubleTapGap = doubleTapGap
    }
}

public enum HotkeyGestureAction: Equatable, Sendable {
    case startHoldRecording
    case stopHoldRecording
    case startToggleRecording
    case stopToggleRecording
}

public final class HotkeyGestureStateMachine: @unchecked Sendable {
    private enum State {
        case idle
        case pressed(Date)
        case holdRecording
        case waitingForSecondTap(Date)
        case secondTapPressed(Date, firstTapRelease: Date)
        case toggleRecording
        case toggleStopPressed
    }

    private var state: State = .idle
    private let config: HotkeyGestureConfig

    public init(config: HotkeyGestureConfig = HotkeyGestureConfig()) {
        self.config = config
    }

    public func reset() {
        state = .idle
    }

    public func keyDown(at time: Date) -> [HotkeyGestureAction] {
        switch state {
        case .idle:
            state = .pressed(time)
        case .waitingForSecondTap(let firstRelease):
            if time.timeIntervalSince(firstRelease) <= config.doubleTapGap {
                state = .secondTapPressed(time, firstTapRelease: firstRelease)
            } else {
                state = .pressed(time)
            }
        case .toggleRecording:
            state = .toggleStopPressed
        default:
            break
        }
        return []
    }

    public func keyUp(at time: Date) -> [HotkeyGestureAction] {
        switch state {
        case .pressed(let down):
            if time.timeIntervalSince(down) >= config.holdThreshold {
                state = .idle
                return [.startHoldRecording, .stopHoldRecording]
            }
            state = .waitingForSecondTap(time)
            return []

        case .holdRecording:
            state = .idle
            return [.stopHoldRecording]

        case .secondTapPressed(_, let firstTapRelease):
            if time.timeIntervalSince(firstTapRelease) <= config.doubleTapGap {
                state = .toggleRecording
                return [.startToggleRecording]
            }
            state = .waitingForSecondTap(time)
            return []

        case .toggleStopPressed:
            state = .idle
            return [.stopToggleRecording]

        default:
            return []
        }
    }

    public func tick(at time: Date) -> [HotkeyGestureAction] {
        switch state {
        case .pressed(let down):
            if time.timeIntervalSince(down) >= config.holdThreshold {
                state = .holdRecording
                return [.startHoldRecording]
            }
            return []

        case .waitingForSecondTap(let firstTapRelease):
            if time.timeIntervalSince(firstTapRelease) > config.doubleTapGap {
                state = .idle
            }
            return []

        default:
            return []
        }
    }
}
