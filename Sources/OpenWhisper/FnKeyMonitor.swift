import ApplicationServices
import CoreGraphics
import Foundation

final class FnKeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnIsDown = false
    private let onChange: @Sendable (Bool) -> Void

    init(onChange: @escaping @Sendable (Bool) -> Void) {
        self.onChange = onChange
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
    }

    func start() throws {
        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }

                let monitor = Unmanaged<FnKeyMonitor>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: opaqueSelf
        ) else {
            throw FnKeyMonitorError.eventTapUnavailable
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        guard type == .flagsChanged else { return }
        let isDown = event.flags.contains(.maskSecondaryFn)
        guard isDown != fnIsDown else { return }

        fnIsDown = isDown
        onChange(isDown)
    }
}

enum FnKeyMonitorError: Error, LocalizedError {
    case eventTapUnavailable

    var errorDescription: String? {
        switch self {
        case .eventTapUnavailable:
            return "Could not create a keyboard event tap. Grant Accessibility permission and relaunch OpenWhisper."
        }
    }
}
