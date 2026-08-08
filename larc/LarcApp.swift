import SwiftUI
import Combine

@main
struct LarcApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Register defaults before anything reads them (DeviceController and
        // AppDelegate's status item are created during launch).
        UserDefaults.standard.register(defaults: SettingsKeys.defaults)
        _ = DeviceController.shared
        // Woken here rather than left to the first screen that reads it.
        //
        // It's a lazy `static let`, and nothing on the main screen touches it,
        // so its `$selectedID` subscription — the whole point of which is to
        // start reading a device's settings the moment one is chosen — didn't
        // exist until the Controls screen was built. That's the screen the
        // subscription is meant to have already filled, so on a first visit it
        // reliably arrived empty and populated a round trip later.
        _ = DeviceSettingsModel.shared
    }

    // No SwiftUI-managed window/menu bar item: the status item, popover, and
    // onboarding window are all owned by AppDelegate. MenuBarExtra has no
    // public API to toggle its popover programmatically, which the global
    // hotkey needs — a manually-managed NSStatusItem + NSPopover does. An App
    // still needs a Scene; Settings {} creates none since the app has no
    // Settings menu item (LSUIElement, no menu bar).
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var onboardingWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var outsideClickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    /// What we last asked the status item button's highlight to be.
    ///
    /// Deliberately *not* a popover state machine — every open/close decision
    /// reads `popover.isShown` directly. An earlier version tracked popover
    /// state in a parallel enum that AppKit-initiated dismissals (Esc, app
    /// deactivation) never updated, so the shadow state silently went stale
    /// and clicks stopped working until pressed twice. This flag is purely
    /// cosmetic and never consulted for behavior.
    private var wantsHighlight = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            // Relaunching uses `open -n`, which can leave older instances
            // behind; a stale instance also swallows plain `open` (it just
            // activates, showing nothing). Newest instance wins.
            terminateOlderInstances()

            // Silent permission check — never prompts. Prompts are tied to
            // explicit user taps (onboarding, popover toggle).
            MediaKeyTap.shared.start()

            if UserDefaults.standard.bool(forKey: SettingsKeys.hasCompletedOnboarding) {
                setupStatusItem()
                DeviceController.shared.startDiscovery()
                // Dev builds only now that the artwork layers are settled.
                // `./build.sh --dev` to tune them again; the Dev screen has a
                // row that brings this forward.
                #if LARC_DEV
                TuningWindow.show()
                #endif
            } else {
                showOnboarding()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            MediaKeyTap.shared.refreshPermission()
        }
    }

    /// `open` on an already-running app lands here instead of launching a new
    /// process. If onboarding hasn't finished, (re)show it — otherwise the app
    /// would activate with no UI at all.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !UserDefaults.standard.bool(forKey: SettingsKeys.hasCompletedOnboarding) {
            if let window = onboardingWindow {
                NSApp.setActivationPolicy(.regular)
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                showOnboarding()
            }
        }
        return true
    }

    private func terminateOlderInstances() {
        let myPID = NSRunningApplication.current.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "com.studioaiyo.larc"
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        where app.processIdentifier != myPID {
            app.terminate()
        }
    }

    @MainActor
    private func showOnboarding() {
        // LSUIElement apps launch with activationPolicy .accessory, which
        // doesn't reliably take focus from whatever launched it (e.g.
        // Terminal) — that was the real reason the window needed a floating
        // level to stay visible. .regular activates like any normal app, so
        // the window (and any system dialogs it triggers later, like the
        // Accessibility prompt) behave normally with no level hack needed.
        NSApp.setActivationPolicy(.regular)

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: OnboardingView { [weak self] restart in
                UserDefaults.standard.set(true, forKey: SettingsKeys.hasCompletedOnboarding)
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
                NSApp.setActivationPolicy(.accessory)
                self?.setupStatusItem()
                if restart {
                    Relauncher.relaunch()
                }
            }
        )
        // Size explicitly before centering — centering a zero-sized window and
        // letting SwiftUI grow it afterwards leaves it off-center. center()
        // deliberately sits above true center; that's the macOS convention.
        window.setContentSize(NSSize(width: 520, height: 500))
        window.center()
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Status item & popover

    @MainActor
    private func setupStatusItem() {
        guard statusItem == nil else { return }

        // Fixed length, not .variableLength — the button's content alternates
        // between a speaker glyph and a 1-3 digit volume flash, and
        // .variableLength resizes the button to fit that content, which moves
        // the popover's anchor point (it's positioned relativeTo:
        // button.bounds) every time the content changes width.
        //
        // Necessary but not sufficient: the content is also always rendered as
        // one fixed-size image rather than swapping between .image and .title,
        // which was a second, independent source of anchor movement. See
        // menuBarContentSize.
        let item = NSStatusBar.system.statusItem(withLength: 30)
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            // Fires on mouseDOWN, not the default mouseUp — every other
            // menu-bar item (Control Center, battery, Now Playing) opens the
            // instant you press down, not after a full click completes.
            //
            // This also happens to fix a race with .transient dismissal: a
            // click on the icon while the popover is open counts as an
            // outside click, so AppKit would dismiss it on its own. Acting on
            // mouse-down means we see isShown == true and close it ourselves
            // first, instead of running after the auto-dismissal and
            // immediately reopening what the user just closed.
            button.sendAction(on: [.leftMouseDown])
        }
        statusItem = item

        let pop = NSPopover()
        // .applicationDefined, not .transient.
        //
        // .transient dismisses on *any* click outside the popover — including
        // on our own status item — and it does so before the button's action
        // runs. That made "clicking the icon while in a sub-screen goes back"
        // impossible: the popover was already closing by the time we could pop.
        //
        // So dismissal is ours now, and all three cases .transient covered are
        // handled explicitly: outside clicks by `outsideClickMonitor` (which
        // existed already, because .transient never handled clicks on *other*
        // apps' status items), Esc by PopoverHotkeys, and app deactivation by
        // the observer below. Everything about the show/hide animation is still
        // AppKit's — no `animates = false`, no manual fade into the popover's
        // private window; that customization is what made AppKit-initiated
        // closes skip the animation.
        pop.behavior = .applicationDefined

        // `sizingOptions` is not optional here — without it the popover lands in
        // the wrong place on macOS 15, and only there.
        //
        // An NSHostingController that has not been told to publish its size
        // reports something other than what SwiftUI settles on, and AppKit
        // positions the popover against that first answer. Measured on 15.6: the
        // popover sat 40pt left of its status item, and 106pt too high — high
        // enough that the top was clipped off the screen. Reproduced in a
        // twenty-line probe with no larc code in it: every hosting variant
        // *without* a declared size was 40pt off, every variant *with* one was
        // exact.
        //
        // The vertical half follows from the same cause. AppKit places the
        // popover for the size it was given, finds an oversized one doesn't fit
        // below the menu bar, and shifts it up; SwiftUI then settles to the real
        // height and the window keeps the shifted origin — so the top stays
        // clipped while the bottom moves with content. It never appears on a
        // tall screen, because nothing needs shifting there. macOS 26 places it
        // correctly either way, which is why this survived development.
        //
        // `.preferredContentSize` rather than a hardcoded `pop.contentSize`: the
        // popover's height legitimately changes between screens, and a constant
        // would have to be maintained against every layout change.
        let host = NSHostingController(rootView: PopoverView())
        host.sizingOptions = [.preferredContentSize]
        pop.contentViewController = host
        pop.delegate = self
        popover = pop

        // .applicationDefined means AppKit no longer closes the popover when the
        // app loses focus, so that case is restored here. Command-Tabbing away
        // with a menu bar popover still up would otherwise leave it floating
        // over another app's window.
        // Captures the popover rather than self: NotificationCenter's closure is
        // @Sendable, and AppDelegate isn't, so passing the object we actually
        // need keeps the capture legal without weakening isolation.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak pop] _ in
            MainActor.assumeIsolated { pop?.performClose(nil) }
        }

        // Esc, and the escape hatch for anything else that wants the popover
        // shut without reaching for AppKit.
        PopoverNavigation.shared.requestClose = { [weak self] in
            self?.popover?.performClose(nil)
        }

        observeControllerForStatusItem()
        updateMenuBarAppearance()

        GlobalHotKey.shared.register { [weak self] in
            Task { @MainActor in self?.togglePopover(nil) }
        }
    }

    /// The only place the popover is opened or closed. Reads `popover.isShown`
    /// rather than any tracked state, so it can't disagree with AppKit about
    /// whether the popover is up.
    // @MainActor because the navigation stack is main-actor isolated and this
    // consults it; the method only ever runs from a button action anyway.
    @MainActor
    @objc private func togglePopover(_ sender: Any?) {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            // Inside a sub-screen, the icon means "back", not "close" — so a
            // wrong turn costs one click to undo rather than closing the
            // popover and losing your place. Clicking outside still dismisses
            // everything, which is the deliberate way out.
            // …unless the screen has something invalid in it, in which case
            // there is no going back and the icon closes instead. A blocked
            // "back" that also refused to close would leave the icon dead, and
            // closing is the documented way to abandon such an edit.
            if !PopoverNavigation.shared.isAtRoot,
               !PopoverNavigation.shared.popBlocked {
                PopoverNavigation.shared.reset()
                return
            }
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Immediately, synchronously, before the open animation draws its
            // first frame — show() creates and orders the window inline, so the
            // first responder AppKit assigned during it is already clearable
            // here. Doing this only from popoverDidShow (which fires after the
            // animation *finishes*) meant the ring was visible for the whole
            // open animation and then vanished.
            clearInitialFocus()
            // Again next run loop turn, in case the assignment lands just after
            // show() returns rather than inside it.
            DispatchQueue.main.async { [weak self] in self?.clearInitialFocus() }
            // **Make the popover's window key, explicitly.**
            //
            // Opened from the global hotkey the popover could come up in the
            // *inactive* appearance — grey slider, dimmed chrome — and Tab did
            // nothing, because key-window status is what drives both. Clicking
            // the icon fixed it, which is the tell: a click activates the app,
            // a Carbon hot key does not.
            //
            // `NSApp.activate` above is no longer enough on its own; a
            // background app asking to activate without a click is increasingly
            // ignored. Asking the window directly is, and it also restores Tab.
            DispatchQueue.main.async {
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    /// Drops the first responder `NSPopover` assigns to the first focusable
    /// control (the device picker) when it shows. With keyboard navigation
    /// enabled in System Settings that control arrives already ringed, without
    /// the user pressing anything.
    ///
    /// Only clears the *initial* unrequested focus — Tab and "P" focus
    /// normally afterwards. Their focus is what times out on idle, handled
    /// separately in PopoverHotkeys.
    private func clearInitialFocus() {
        popover?.contentViewController?.view.window?.makeFirstResponder(nil)
    }

    // MARK: - Status item highlight

    /// The pale rounded background every menu bar item shows while its panel
    /// is open. A custom status item doesn't get this for free the way a
    /// system one does, so it has to be driven explicitly.
    private func applyHighlight() {
        guard let button = statusItem?.button else { return }
        // Only assign on a real change — an unconditional set marks the
        // button for redisplay on every status poll.
        if button.isHighlighted != wantsHighlight {
            button.isHighlighted = wantsHighlight
        }
    }

    /// NSButtonCell owns `isHighlighted` for the duration of a press and
    /// clears it when the mouse comes up — which happens *after* our
    /// mouse-down action has already opened the popover and set the
    /// highlight. There's no observable "cell finished tracking" hook, so the
    /// value is reasserted at three points spanning the release. applyHighlight
    /// is a no-op when nothing changed, so the extra calls are free.
    private func syncHighlight() {
        applyHighlight()
        DispatchQueue.main.async { [weak self] in self?.applyHighlight() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.applyHighlight() }
    }

    // MARK: - Popover delegate

    func popoverWillShow(_ notification: Notification) {
        wantsHighlight = true
        syncHighlight()

        DeviceController.shared.popoverOpen = true
        MediaKeyTap.shared.refreshPermissionAsync()
        PopoverHotkeys.shared.start()

        // A transient NSPopover's built-in outside-click dismissal doesn't
        // fire for clicks on OTHER apps' status items (SystemUIServer menu-bar
        // extras like Now Playing/Control Center/clock) — those don't trigger
        // the app-activation-change signal the built-in behavior relies on.
        //
        // Clicks on our OWN status item are visible to this monitor too, since
        // status items are SystemUIServer-hosted rather than literally part of
        // "our app's windows" the way Apple's global-monitor docs imply is
        // excluded. Those are already handled by the button's own action, so
        // they're skipped here to avoid restarting the close animation.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            if let button = self.statusItem?.button, let window = button.window {
                let buttonFrameOnScreen = window.convertToScreen(button.convert(button.bounds, to: nil))
                if buttonFrameOnScreen.contains(NSEvent.mouseLocation) {
                    return
                }
            }
            Task { @MainActor in self.popover?.performClose(nil) }
        }
    }

    /// Final catch for the initial-focus clear. Fires after the open animation
    /// finishes, so it's far too late to be the *only* place this happens (that
    /// was the visible ring flash) — the real work is done inline in
    /// togglePopover. Kept because it costs nothing and guarantees the ring
    /// can never persist if AppKit assigns focus later than expected.
    func popoverDidShow(_ notification: Notification) {
        clearInitialFocus()
    }

    /// Fires before the close animation starts, unlike popoverDidClose — so
    /// the highlight clears in response to the click rather than lagging
    /// behind the whole animation.
    func popoverWillClose(_ notification: Notification) {
        wantsHighlight = false
        applyHighlight()
    }

    @MainActor
    func popoverDidClose(_ notification: Notification) {
        wantsHighlight = false
        applyHighlight()

        // Back to the root, so the next open always starts on the main screen.
        // Resuming three levels deep in a preset editor would be disorienting
        // when the popover is opened by a global hotkey or a media key.
        PopoverNavigation.shared.reset()
        DeviceController.shared.popoverOpen = false
        PopoverHotkeys.shared.stop()
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    /// Menu bar label: the speaker glyph (reflecting mute/volume), or the
    /// numeric volume flash for 1.5s after a change — same rendering
    /// `MenuBarExtra`'s label closure used to do, just driven by Combine
    /// instead of SwiftUI view invalidation.
    ///
    /// Each sink defers its read via DispatchQueue.main.async rather than
    /// calling updateMenuBarAppearance() inline — @Published's synthesized
    /// publisher fires on willSet, i.e. BEFORE the property is actually
    /// stored, so reading `controller.status` synchronously inside the sink
    /// sees the OLD value; the menu bar then looks permanently "one change
    /// behind" (only catching up on the next change), which reads exactly
    /// like network-latency lag but has nothing to do with the network — the
    /// app already updates optimistically before any request completes.
    /// Deferring one run loop tick guarantees the real assignment has landed.
    @MainActor
    private func observeControllerForStatusItem() {
        let controller = DeviceController.shared
        func deferredUpdate() {
            DispatchQueue.main.async { [weak self] in self?.updateMenuBarAppearance() }
        }
        controller.$volumeFlash.sink { _ in deferredUpdate() }.store(in: &cancellables)
        controller.$status.sink { _ in deferredUpdate() }.store(in: &cancellables)
        controller.$devices.sink { _ in deferredUpdate() }.store(in: &cancellables)
        controller.$selectedID.sink { _ in deferredUpdate() }.store(in: &cancellables)
    }

    @MainActor
    private func updateMenuBarAppearance() {
        guard let button = statusItem?.button else { return }
        let controller = DeviceController.shared
        // Always an image, never a title — see menuBarContentSize.
        button.title = ""
        button.imagePosition = .imageOnly
        if let flash = controller.volumeFlash {
            button.image = menuBarImage(drawing: .text("\(flash)"))
        } else {
            button.image = menuBarImage(drawing: .symbol(menuBarSymbolName(controller)))
        }
        // Reasserted here so the "active" highlight survives every appearance
        // refresh while the popover is open, in case reassigning .image/.title
        // resets it.
        applyHighlight()
    }

    // MARK: - Menu bar content rendering

    /// Every possible menu bar content — each speaker glyph and each numeric
    /// volume flash — is drawn into an image of exactly this size, and
    /// `button.title` is always empty.
    ///
    /// This is not cosmetic, it's the fix for the popover jumping vertically.
    /// The popover anchors to `button.bounds`, and the old code swapped the
    /// button between `.image` (a symbol, whose intrinsic size differs per
    /// glyph) and `.title` (a number) — an image-only button and a title-only
    /// button do not present the same anchor, so the popover moved every time
    /// the flash appeared or expired. Diagnosed 2026-07-26 from the decisive
    /// observation that the shift tracks *image vs. number*, at any volume,
    /// and not volume 0 or mute as had been assumed across roughly six earlier
    /// attempts at this bug.
    ///
    /// One content type and one fixed size removes the variable instead of
    /// compensating for it. **Don't reintroduce `button.title`.**
    private static let menuBarContentSize = NSSize(width: 26, height: 18)

    private enum MenuBarContent {
        case symbol(String)
        case text(String)
    }

    /// Draws either a symbol or a string centred in a fixed-size template
    /// image. Template means only alpha matters, so the drawing colour is
    /// irrelevant and the system tints it for light/dark and for the
    /// highlighted state, exactly as it did with a plain symbol image.
    @MainActor
    private func menuBarImage(drawing content: MenuBarContent) -> NSImage? {
        let size = Self.menuBarContentSize
        var symbol: NSImage?
        if case let .symbol(name) = content {
            guard let base = NSImage(systemSymbolName: name, accessibilityDescription: "Larc") else {
                return nil
            }
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            symbol = base.withSymbolConfiguration(config) ?? base
        }

        let image = NSImage(size: size, flipped: false) { rect in
            switch content {
            case .symbol:
                guard let symbol else { return false }
                let s = symbol.size
                symbol.draw(in: NSRect(x: rect.midX - s.width / 2,
                                       y: rect.midY - s.height / 2,
                                       width: s.width,
                                       height: s.height))
            case .text(let string):
                let attributed = NSAttributedString(string: string, attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.black,
                ])
                let textSize = attributed.size()
                attributed.draw(at: NSPoint(x: rect.midX - textSize.width / 2,
                                            y: rect.midY - textSize.height / 2))
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    @MainActor
    private func menuBarSymbolName(_ controller: DeviceController) -> String {
        guard let status = controller.status, controller.selectedDevice != nil else {
            return "speaker.wave.2"
        }
        if status.muted {
            return "speaker.slash"
        }
        switch status.volume {
        case 0: return "speaker"
        case 1...35: return "speaker.wave.1"
        case 36...70: return "speaker.wave.2"
        default: return "speaker.wave.3"
        }
    }
}

/// Relaunches the app. Needed after granting Accessibility: macOS applies the
/// grant to a freshly launched process; the running one can keep failing the
/// check (and tap creation) until restarted.
enum Relauncher {
    @MainActor
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // `sleep` lets this process exit first so `open -n` starts a clean
        // instance instead of poking the dying one.
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open -n \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}
