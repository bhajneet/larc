import Carbon.HIToolbox
import AppKit

/// A single system-wide keyboard shortcut (default Cmd+Ctrl+L, opens the
/// popover) registered via the Carbon Hot Key Manager
/// (`RegisterEventHotKey`/`InstallEventHandler`), not a CGEventTap. This is
/// the sandbox-safe way to claim an ordinary key+modifier chord globally —
/// no Accessibility or Input Monitoring permission, no TCC prompt at all —
/// which is what makes it usable from both Larc (App Store) and Larc Keys.
/// Mechanically unrelated to `MediaKeyTap`: that handles NX_SYSDEFINED media
/// keys, which this API cannot see; this handles regular key+modifier combos,
/// which a CGEventTap would need Accessibility for.
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?

    private static let signature: FourCharCode = 0x4C61_724B // 'LarK'

    private init() {}

    /// Registers the global shortcut. Safe to call once at app launch; a
    /// second call replaces the action but does not re-register the key.
    func register(
        keyCode: UInt32 = UInt32(kVK_ANSI_L),
        modifiers: UInt32 = UInt32(cmdKey | controlKey),
        action: @escaping () -> Void
    ) {
        self.action = action
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            hotKey.action?()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        eventHandler = nil
    }
}
