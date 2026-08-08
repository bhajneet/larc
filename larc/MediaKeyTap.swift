import AppKit
import Combine

/// Intercepts media keys (volume up/down, mute, play, next, previous) with a
/// CGEventTap on NX_SYSDEFINED events (subtype 8). Keys enabled in Settings are
/// consumed — macOS never sees them, so the Mac's own volume does not change —
/// and routed to the selected network device. Disabled keys pass through.
///
/// Requires Accessibility permission (checked via AXIsProcessTrusted).
@MainActor
final class MediaKeyTap: ObservableObject {
    static let shared = MediaKeyTap()

    @Published private(set) var accessibilityGranted = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var pollTimer: Timer?

    private init() {}

    /// Silent start: checks the current permission state and installs the tap
    /// if possible. Never triggers the system prompt — prompting is reserved
    /// for explicit user actions (onboarding button, popover toggle).
    func start() {
        refreshPermission()
        startPollingIfNeeded()
    }

    /// Fires the system Accessibility prompt (no-op if already granted).
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let granted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        apply(granted: granted)
        startPollingIfNeeded()
    }

    /// Re-checks Accessibility permission. Called on app activation and a
    /// slow poll (while ungranted) — LSUIElement apps rarely "activate", so
    /// activation alone would miss a grant made in System Settings.
    func refreshPermission() {
        apply(granted: AXIsProcessTrusted())
    }

    /// Same check, off the main thread — AXIsProcessTrusted talks to tccd via
    /// XPC and can briefly block. Used on popover open so a permission
    /// *revoked* after an earlier grant is still caught (polling stops once
    /// granted, by design, so that path alone wouldn't notice) without
    /// stalling the popover's appearance.
    func refreshPermissionAsync() {
        DispatchQueue.global(qos: .userInitiated).async {
            let granted = AXIsProcessTrusted()
            Task { @MainActor in
                MediaKeyTap.shared.apply(granted: granted)
            }
        }
    }

    private func apply(granted: Bool) {
        if granted != accessibilityGranted {
            accessibilityGranted = granted
        }
        if granted {
            pollTimer?.invalidate()
            pollTimer = nil
            installTapIfPossible()
        } else {
            removeTap()
            startPollingIfNeeded()
        }
    }

    /// Tears down the live tap when a prior grant is revoked — capturedAction
    /// already gates on mediaKeysEnabled, but leaving the tap installed with
    /// stale trust would mean the UI (correctly) shows "waiting for
    /// Accessibility" while keys might still silently be captured.
    private func removeTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(tap)
        eventTap = nil
        runLoopSource = nil
    }

    private func startPollingIfNeeded() {
        guard !accessibilityGranted, pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in
                MediaKeyTap.shared.refreshPermission()
            }
        }
    }

    private func installTapIfPossible() {
        guard accessibilityGranted, eventTap == nil else { return }

        let mask = CGEventMask(1 << NX_SYSDEFINED)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                MediaKeyTap.handle(type: type, event: event)
            },
            userInfo: nil
        ) else { return }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Static so the C callback closure captures nothing.
    private static func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables the tap if the process stalls; re-enable and pass through.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async {
                if let tap = MediaKeyTap.shared.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard type.rawValue == UInt32(NX_SYSDEFINED),
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int32((nsEvent.data1 & 0xFFFF_0000) >> 16)
        let keyFlags = nsEvent.data1 & 0x0000_FFFF
        let keyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A

        guard let action = MediaKeyMapping.action(for: keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        // Consume both key-down and key-up of captured keys; act on key-down.
        if keyDown {
            DispatchQueue.main.async { action() }
        }
        return nil
    }
}
