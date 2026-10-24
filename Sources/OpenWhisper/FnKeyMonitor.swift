import AppKit
import Foundation

final class FnKeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var fnIsDown = false
    /// Whether fn is down and when it moved, in seconds since startup. That time comes from the key event
    /// itself, so it stays accurate when the event is handled late.
    private let onChange: @Sendable (Bool, TimeInterval) -> Void

    init(onChange: @escaping @Sendable (Bool, TimeInterval) -> Void) {
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() throws {
        guard globalMonitor == nil, localMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event: event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event: event)
            return event
        }

        guard globalMonitor != nil || localMonitor != nil else {
            throw FnKeyMonitorError.monitorUnavailable
        }
    }

    private func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(event: NSEvent) {
        let isDown = event.modifierFlags.contains(.function)
        guard isDown != fnIsDown else { return }

        fnIsDown = isDown
        onChange(isDown, Self.time(of: event))
    }

    /// Events posted by other apps can carry no time at all, so those count as happening now.
    private static func time(of event: NSEvent) -> TimeInterval {
        let now = ProcessInfo.processInfo.systemUptime
        return (now - longestEventDelay...now).contains(event.timestamp) ? event.timestamp : now
    }

    private static let longestEventDelay: TimeInterval = 10
}

enum FnKeyMonitorError: Error, LocalizedError {
    case monitorUnavailable

    var errorDescription: String? {
        switch self {
        case .monitorUnavailable:
            return "Could not start keyboard monitoring. Grant Accessibility permission and relaunch OpenWhisper."
        }
    }
}
