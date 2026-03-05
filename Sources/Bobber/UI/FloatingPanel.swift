import AppKit
import SwiftUI

class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private static let idleAlpha: CGFloat = 0.55
    private static let activeAlpha: CGFloat = 1.0

    private var isMouseInside = false
    private var trackingArea: NSTrackingArea?

    // Deliver first click immediately instead of requiring focus first
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }

    override func becomeKey() {
        super.becomeKey()
        updateAlpha()
    }

    override func resignKey() {
        super.resignKey()
        updateAlpha()
    }

    private func updateAlpha() {
        let target = (isMouseInside || isKeyWindow) ? Self.activeAlpha : Self.idleAlpha
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.animator().alphaValue = target
        }
    }

    private func setupTrackingArea() {
        guard let contentView else { return }
        if let old = trackingArea { contentView.removeTrackingArea(old) }
        let area = NSTrackingArea(
            rect: contentView.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView.addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        updateAlpha()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        updateAlpha()
    }

    init(contentView: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.titleVisibility = .hidden

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true

        // Behind: blur layer
        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(blur)

        // Front: transparent SwiftUI content
        let hostingView = ClickHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostingView)

        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: container.topAnchor),
            blur.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        self.contentView = container
        self.alphaValue = Self.idleAlpha
        setupTrackingArea()
    }

}
