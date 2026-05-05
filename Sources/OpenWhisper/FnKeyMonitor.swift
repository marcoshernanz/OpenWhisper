import AppKit
import Foundation

final class FnKeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var fnIsDown = false
    private let onChange: @Sendable (Bool) -> Void

    init(onChange: @escaping @Sendable (Bool) -> Void) {
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
        onChange(isDown)
    }
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
