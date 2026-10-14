import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class OverlayController: NSObject, NSWindowDelegate {
    static let shared = OverlayController()

    private var panel: NSPanel?
    private var hosting: NSHostingController<OverlayView>?
    private var settingsWindow: NSWindow?
    private var monitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var lastToggleAt: TimeInterval = 0
    private let frameAnimator = FrameAnimator()

    func start() {
        if panel == nil {
            panel = makePanel()
        }
        bind()
        apply(animated: false)
        panel?.orderFrontRegardless()
    }

    func apply(animated: Bool = false) {
        guard let panel else { return }
        let target = frame(expanded: AppState.shared.expanded, signedIn: AppState.shared.signedIn)
        if animated {
            frameAnimator.animate(panel: panel, to: target, duration: 0.18)
        } else {
            frameAnimator.cancel()
            panel.setFrame(target, display: true)
        }
    }

    func handleRightClick() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastToggleAt > 0.2 else { return }
        lastToggleAt = now
        if AppState.shared.overlayHidden {
            AppState.shared.setOverlayHidden(false)
            return
        }
        AppState.shared.toggleExpanded()
    }

    func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView().environmentObject(AppState.shared)
            let hosting = NSHostingController(rootView: AnyView(view))
            // AppKit owns this fixed-size window; avoid fitting-size feedback.
            hosting.sizingOptions = []
            let window = NSWindow(contentViewController: hosting)
            window.title = "Todaytape"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 460, height: 740))
            window.contentMinSize = NSSize(width: 420, height: 420)
            window.level = .floating
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("TodaytapeSettings")
            settingsWindow = window
        }
        if settingsWindow?.isVisible == false { settingsWindow?.center() }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === settingsWindow else { return }
        // A closed hosting controller would otherwise keep observing app state.
        window.contentViewController = nil
        settingsWindow = nil
    }

    private func frame(expanded: Bool, signedIn: Bool) -> NSRect {
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let contentWidth: CGFloat
        let contentHeight: CGFloat
        if AppState.shared.overlayHidden && signedIn {
            let width = OverlayMetrics.grabberWidth
            let height = OverlayMetrics.grabberHeight
            return NSRect(
                x: screen.maxX - width,
                y: screen.midY - height / 2,
                width: width,
                height: height
            )
        }
        if !signedIn {
            contentWidth = OverlayMetrics.expandedWidth
            contentHeight = 88
        } else {
            contentWidth = expanded ? OverlayMetrics.expandedWidth : OverlayMetrics.slimWidth
            contentHeight = min(screen.height - 48, screen.height * OverlayMetrics.tapeHeightFraction)
        }
        let width = contentWidth + OverlayMetrics.panelExtraWidth
        let height = contentHeight + OverlayMetrics.panelExtraHeight
        return NSRect(
            x: screen.maxX - contentWidth - OverlayMetrics.rightMargin - OverlayMetrics.shadowPadLeading,
            y: screen.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: frame(expanded: false, signedIn: true),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true

        let hosting = NSHostingController(rootView: OverlayView(state: AppState.shared))
        hosting.view.wantsLayer = true
        hosting.view.clipsToBounds = false
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.view.layer?.masksToBounds = false
        hosting.view.layer?.shadowOpacity = 0
        hosting.view.shadow = nil
        panel.contentViewController = hosting
        self.hosting = hosting

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            guard event.window == panel else { return event }
            guard AppState.shared.signedIn else { return event }
            if AppState.shared.overlayHidden {
                AppState.shared.setOverlayHidden(false)
                return nil
            }
            guard event.type == .rightMouseDown else { return event }
            self.handleRightClick()
            return nil
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.apply(animated: false) }
        }

        return panel
    }

    private func bind() {
        cancellables.removeAll()
        AppState.shared.$phase
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.apply(animated: false) }
            .store(in: &cancellables)
        AppState.shared.$events
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.apply(animated: false) }
            .store(in: &cancellables)
    }
}

/// Per-frame window resize so expand/collapse tracks the display refresh rate.
private final class FrameAnimator: NSObject {
    private var link: CADisplayLink?
    private weak var panel: NSPanel?
    private var from = NSRect.zero
    private var to = NSRect.zero
    private var start: CFTimeInterval = 0
    private var duration: CFTimeInterval = 0.18

    func cancel() {
        link?.invalidate()
        link = nil
        panel = nil
    }

    func animate(panel: NSPanel, to target: NSRect, duration: CFTimeInterval) {
        cancel()
        self.panel = panel
        from = panel.frame
        to = target
        self.duration = max(duration, 0.05)
        start = CACurrentMediaTime()

        guard let view = panel.contentView else {
            panel.setFrame(target, display: true)
            return
        }
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let panel else {
            cancel()
            return
        }
        let t = min(1, (CACurrentMediaTime() - start) / duration)
        let e = easeOutCubic(t)
        panel.setFrame(lerp(from, to, e), display: true)
        if t >= 1 {
            panel.setFrame(to, display: true)
            cancel()
        }
    }

    private func easeOutCubic(_ t: CFTimeInterval) -> CGFloat {
        let p = 1 - t
        return CGFloat(1 - p * p * p)
    }

    private func lerp(_ a: NSRect, _ b: NSRect, _ t: CGFloat) -> NSRect {
        NSRect(
            x: a.origin.x + (b.origin.x - a.origin.x) * t,
            y: a.origin.y + (b.origin.y - a.origin.y) * t,
            width: a.size.width + (b.size.width - a.size.width) * t,
            height: a.size.height + (b.size.height - a.size.height) * t
        )
    }
}
