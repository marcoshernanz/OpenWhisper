import AppKit

@MainActor
final class DictationOverlayWindowController: NSWindowController {
    private let overlayView = DictationOverlayView()
    private var targetFrame: NSRect = .zero
    private var hideWorkItem: DispatchWorkItem?

    init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 168, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.isMovable = false
        window.isOpaque = false
        window.level = .statusBar
        window.contentView = overlayView

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }

        hideWorkItem?.cancel()
        targetFrame = frameForCurrentScreen()
        let startFrame = targetFrame.offsetBy(dx: 0, dy: -10)

        overlayView.updateLevel(0)
        overlayView.startAnimating()
        window.setFrame(startFrame, display: true)
        window.alphaValue = 0.35
        window.orderFrontRegardless()
        window.display()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(targetFrame, display: true)
        }
    }

    func hide() {
        guard let window, window.isVisible else { return }

        hideWorkItem?.cancel()
        let endFrame = targetFrame.offsetBy(dx: 0, dy: -8)
        let workItem = DispatchWorkItem { [weak self, weak window] in
            window?.orderOut(nil)
            self?.overlayView.stopAnimating()
            self?.overlayView.updateLevel(0)
        }
        hideWorkItem = workItem

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
            window.animator().setFrame(endFrame, display: true)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: workItem)
    }

    func updateLevel(_ level: Float) {
        overlayView.updateLevel(CGFloat(level))
    }

    private func frameForCurrentScreen() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 168, height: 52)
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 22
        )
        return NSRect(origin: origin, size: size)
    }
}

private final class DictationOverlayView: NSView {
    private let waveformView = DictationWaveformView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        addSubview(waveformView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        waveformView.frame = bounds.insetBy(dx: 26, dy: 12)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let pillRect = bounds.insetBy(dx: 7, dy: 8)
        let path = NSBezierPath(roundedRect: pillRect, xRadius: pillRect.height / 2, yRadius: pillRect.height / 2)

        NSColor(calibratedWhite: 0.07, alpha: 0.84).setFill()
        path.fill()

        NSColor(calibratedWhite: 1, alpha: 0.14).setStroke()
        path.lineWidth = 1
        path.stroke()

        let glowRect = pillRect.insetBy(dx: 1, dy: 1)
        let glowPath = NSBezierPath(roundedRect: glowRect, xRadius: glowRect.height / 2, yRadius: glowRect.height / 2)
        NSColor(calibratedWhite: 1, alpha: 0.05).setStroke()
        glowPath.lineWidth = 1
        glowPath.stroke()
    }

    func startAnimating() {
        waveformView.startAnimating()
    }

    func stopAnimating() {
        waveformView.stopAnimating()
    }

    func updateLevel(_ level: CGFloat) {
        waveformView.updateLevel(level)
    }
}

private final class DictationWaveformView: NSView {
    private var timer: Timer?
    private var targetLevel: CGFloat = 0
    private var displayLevel: CGFloat = 0
    private var phase: CGFloat = 0

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func startAnimating() {
        guard timer == nil else { return }

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        targetLevel = 0
        displayLevel = 0
        needsDisplay = true
    }

    func updateLevel(_ level: CGFloat) {
        targetLevel = min(1, max(0, level))
    }

    private func tick() {
        phase += 0.16
        displayLevel += (targetLevel - displayLevel) * 0.22
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let barCount = 11
        let barWidth: CGFloat = 3
        let gap: CGFloat = 4
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
        let startX = bounds.midX - totalWidth / 2
        let centerY = bounds.midY
        let liveLevel = max(displayLevel, 0.04)

        for index in 0..<barCount {
            let distance = abs(CGFloat(index) - CGFloat(barCount - 1) / 2)
            let falloff = 1 - min(0.72, distance / CGFloat(barCount))
            let wave = 0.62 + 0.38 * sin(phase + CGFloat(index) * 0.76)
            let reactiveHeight = liveLevel * 22 * falloff * wave
            let height = max(5, min(bounds.height - 4, 6 + reactiveHeight))
            let x = startX + CGFloat(index) * (barWidth + gap)
            let rect = NSRect(
                x: x,
                y: centerY - height / 2,
                width: barWidth,
                height: height
            )
            let path = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)

            NSColor(calibratedWhite: 1, alpha: 0.98 - distance * 0.035).setFill()
            path.fill()
        }
    }
}
