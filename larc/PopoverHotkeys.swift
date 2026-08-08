import AppKit
import Carbon.HIToolbox
import Combine

/// Ordinary keyboard shortcuts scoped to the popover — plain NSEvent keyDown,
/// not NX_SYSDEFINED media keys, so unlike MediaKeyTap this needs no
/// Accessibility/CGEventTap at all and works in both builds. Full key→action
/// table lives in CLAUDE.md.
///
/// Left/Right (no modifier) and Tab/Shift+Tab are deliberately never given a
/// case here, so whatever SwiftUI control has focus (volume slider, a
/// toggle, the device Picker) keeps its own native behavior untouched, and
/// normal focus traversal isn't broken. Focus rings aren't *drawn* anymore
/// (see PopoverView's focusEffectDisabled) but focus itself still works, and
/// these keys are what make the popover usable without it.
@MainActor
final class PopoverHotkeys: ObservableObject {
    static let shared = PopoverHotkeys()

    /// PopoverView shows per-control hint badges while this is true. Set by
    /// "?"; auto-clears itself after 3s (see `showHints`).
    @Published private(set) var hintsVisible = false
    private var hideTask: Task<Void, Never>?

    /// Bumped on "P". PopoverView observes this to move keyboard focus to the
    /// device picker — a fresh UUID each time, since a Bool can't signal a
    /// repeat press of the same state.
    ///
    /// Focus only: SwiftUI's `Picker` has no API to open its menu, and the
    /// `NSPopUpButton` representable that would is what corrupted the popover's
    /// layout twice. Space does open it though — that's stock `NSPopUpButton`
    /// behavior once focused, and Space is deliberately not a hotkey here so it
    /// reaches the control. Hence the "P ␣" badge: press P, then Space.
    @Published private(set) var focusDeviceRequestID = UUID()

    private var monitor: Any?

    /// Clears keyboard focus after 3 s without a key press, returning the
    /// popover to its just-opened state: nothing focused, so the ring is gone
    /// and the next Tab starts from the first control rather than resuming
    /// mid-list. Applies to focus from Tab and from "P" alike.
    ///
    /// Restarted on *every* keyDown, handled or not — Tab and Shift+Tab are
    /// deliberately not handled as hotkeys, but they still need to count as
    /// activity, or tabbing would be cut off mid-traversal.
    private var focusIdleTask: Task<Void, Never>?

    /// The window keystrokes are arriving in, i.e. the popover's own. Taken
    /// from the event rather than looked up via `NSApp.keyWindow`, which
    /// proved unreliable for exactly this purpose in an earlier attempt.
    private weak var keyEventWindow: NSWindow?

    /// Cmd/Ctrl + these keys jump straight to a volume preset: N×3 up to
    /// N×14 (N = the Volume Step setting), in physical key-row order.
    private static let presetMultiplier: [Int: Int] = [
        kVK_ANSI_1: 3, kVK_ANSI_2: 4, kVK_ANSI_3: 5, kVK_ANSI_4: 6,
        kVK_ANSI_5: 7, kVK_ANSI_6: 8, kVK_ANSI_7: 9, kVK_ANSI_8: 10,
        kVK_ANSI_9: 11, kVK_ANSI_0: 12, kVK_ANSI_Minus: 13, kVK_ANSI_Equal: 14,
    ]

    private init() {}

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Never steal keys from a text field. Preset names are typed in the
            // popover, and every letter here is a shortcut — "M" would mute the
            // device instead of typing an M, and the arrows would change the
            // volume instead of moving the caret. Checked against the first
            // responder rather than a flag, so it stays correct however many
            // text fields the sub-screens grow.
            if let responder = event.window?.firstResponder,
               responder is NSTextView || responder is NSTextField {
                return event
            }
            self.restartFocusIdleTimer(window: event.window)
            // Tab is never consumed (traversal has to stay native), but it's a
            // good moment to surface the hint badges: someone reaching for Tab
            // is hunting for a control, and the badges show the faster way to
            // get there. Shares the same 3 s auto-hide as "?", and restarts on
            // each press, so hints and the focus ring expire together.
            if Int(event.keyCode) == kVK_Tab {
                self.showHints()
            }
            return self.handle(event) ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        focusIdleTask?.cancel()
        focusIdleTask = nil
        keyEventWindow = nil
        hide()
    }

    private func restartFocusIdleTimer(window: NSWindow?) {
        if let window {
            keyEventWindow = window
        }
        focusIdleTask?.cancel()
        focusIdleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            keyEventWindow?.makeFirstResponder(nil)
        }
    }

    /// Shows the per-control hint badges and schedules them to clear
    /// themselves after 3s. Pressing "?" again while visible just restarts
    /// the 3s window rather than hiding immediately.
    private func showHints() {
        hintsVisible = true
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            hintsVisible = false
        }
    }

    private func hide() {
        hideTask?.cancel()
        hideTask = nil
        hintsVisible = false
    }

    /// Returns true if the key was handled (and should be consumed, i.e. not
    /// passed on to whatever SwiftUI control has focus).
    private func handle(_ event: NSEvent) -> Bool {
        let controller = DeviceController.shared
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmdOrCtrl = mods.contains(.command) || mods.contains(.control)
        let cmdOrOpt = mods.contains(.command) || mods.contains(.option)
        // "Plain" = none of cmd/ctrl/option. Shift alone still counts as
        // plain — e.g. "_"/"+" (shifted -/=) and "M"/"J"/"K"/"L"
        // (shifted letters) behave the same as their unshifted key.
        let plain = !mods.contains(.command) && !mods.contains(.control) && !mods.contains(.option)
        let keyCode = Int(event.keyCode)

        // Esc used to be AppKit's job, when the popover was .transient. It is
        // .applicationDefined now — so that clicking the menu bar icon inside a
        // sub-screen can go back instead of closing — which means nothing
        // dismisses the popover unless we do.
        if plain, keyCode == kVK_Escape {
            PopoverNavigation.shared.escape()
            return true
        }

        if cmdOrCtrl, let multiplier = Self.presetMultiplier[keyCode] {
            setPreset(multiplier: multiplier, controller: controller)
            return true
        }

        switch keyCode {
        case kVK_UpArrow where plain:
            controller.stepVolume(+1)
        case kVK_DownArrow where plain:
            controller.stepVolume(-1)
        case kVK_ANSI_Minus where plain:
            controller.stepVolume(-1)
        case kVK_ANSI_Equal where plain:
            controller.stepVolume(+1)
        case kVK_ANSI_M where plain:
            controller.toggleMute()
        case kVK_ANSI_P where plain:
            focusDeviceRequestID = UUID()
        case kVK_ANSI_J where plain:
            controller.previousTrack()
        case kVK_ANSI_K where plain:
            controller.playPause()
        case kVK_ANSI_L where plain:
            controller.nextTrack()
        case kVK_LeftArrow where cmdOrOpt:
            controller.previousTrack()
        case kVK_RightArrow where cmdOrOpt:
            controller.nextTrack()
        case kVK_ANSI_Slash where mods == .shift:
            showHints()
        default:
            return false
        }
        return true
    }

    private func setPreset(multiplier: Int, controller: DeviceController) {
        let step = VolumeStepStore.step(for: DeviceController.shared.selectedID)
        controller.userSetVolume(Double(min(100, step * multiplier)))
    }
}
