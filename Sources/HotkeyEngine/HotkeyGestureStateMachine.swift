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
        case let .waitingForSecondTap(firstRelease):
            if time.timeIntervalSince(firstRelease) <= config.doubleTapGap {
                state = .toggleRecording
                return [.startToggleRecording]
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
        case .pressed:
            state = .waitingForSecondTap(time)
            return []

        case .holdRecording:
            state = .idle
            return [.stopHoldRecording]

        case .toggleStopPressed:
            state = .idle
            return [.stopToggleRecording]

        default:
            return []
        }
    }

    public func nextActionDeadline(at time: Date) -> Date? {
        switch state {
        case let .pressed(down):
            let deadline = down.addingTimeInterval(config.holdThreshold)
            return deadline > time ? deadline : time
        case let .waitingForSecondTap(firstTapRelease):
            let deadline = firstTapRelease.addingTimeInterval(config.doubleTapGap)
            return deadline > time ? deadline : time
        default:
            return nil
        }
    }

    public func tick(at time: Date) -> [HotkeyGestureAction] {
        switch state {
        case let .pressed(down):
            if time.timeIntervalSince(down) >= config.holdThreshold {
                state = .holdRecording
                return [.startHoldRecording]
            }
            return []

        case let .waitingForSecondTap(firstTapRelease):
            if time.timeIntervalSince(firstTapRelease) > config.doubleTapGap {
                state = .idle
            }
            return []

        default:
            return []
        }
    }
}
