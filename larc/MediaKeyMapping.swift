import Foundation

/// NX media key codes and the action each maps to. Used by `MediaKeyTap`
/// (global CGEventTap capture, Accessibility-gated, Larc Keys only).
///
/// Kept as a separate type rather than inlined into MediaKeyTap because the
/// App Store target excludes MediaKeyTap entirely (see the Larc Keys plan) —
/// the mapping is the part worth keeping stable across that split.
///
/// MainActor-isolated so the closures it returns (referencing
/// `DeviceController.shared`, also MainActor-isolated) type-check at the
/// point they're created — `MediaKeyTap.handle` is itself lexically inside a
/// MainActor-isolated method, so the call is same-actor/synchronous.
@MainActor
enum MediaKeyMapping {
    // NX key codes for media keys (IOKit/hidsystem/ev_keymap.h).
    static let soundUp: Int32 = 0    // NX_KEYTYPE_SOUND_UP
    static let soundDown: Int32 = 1  // NX_KEYTYPE_SOUND_DOWN
    static let mute: Int32 = 7       // NX_KEYTYPE_MUTE
    static let play: Int32 = 16      // NX_KEYTYPE_PLAY
    static let next: Int32 = 17      // NX_KEYTYPE_NEXT
    static let previous: Int32 = 18  // NX_KEYTYPE_PREVIOUS
    static let fast: Int32 = 19      // NX_KEYTYPE_FAST
    static let rewind: Int32 = 20    // NX_KEYTYPE_REWIND

    /// Returns the handler for a media key, or nil to let the event through to
    /// the Mac untouched.
    ///
    /// Not all-or-nothing, because volume and transport fail differently:
    ///
    /// - **Unreachable, or no device selected** — nothing is passed to. Before
    ///   this the key was consumed and then silently did nothing, which is worse
    ///   than not capturing it: a sleeping WiiM made the Mac's own volume keys
    ///   appear broken.
    /// - **Passthrough input** — transport goes to the Mac, volume stays here.
    ///   The two are not the same question: the WiiM is still the amplifier on
    ///   optical, so its volume is exactly what the keys should move, while
    ///   play/pause there only gates its output and leaves the source running.
    ///   When the Mac is what feeds the cable, the Mac is what should pause.
    static func action(for keyCode: Int32) -> (() -> Void)? {
        guard UserDefaults.standard.bool(forKey: SettingsKeys.mediaKeysEnabled) else { return nil }

        let controller = DeviceController.shared
        guard controller.reachable, controller.selectedDevice != nil else { return nil }

        switch keyCode {
        case play, next, fast, previous, rewind:
            // Held rather than read from `status`, which blinks to nil whenever
            // the device idles. Unknown input defaults to offering transport.
            guard controller.currentInput?.supportsTransport ?? true else { return nil }
        default:
            break
        }

        switch keyCode {
        case soundUp:
            return { DeviceController.shared.stepVolume(+1) }
        case soundDown:
            return { DeviceController.shared.stepVolume(-1) }
        case mute:
            return { DeviceController.shared.toggleMute() }
        case play:
            return { DeviceController.shared.playPause() }
        case next, fast:
            return { DeviceController.shared.nextTrack() }
        case previous, rewind:
            return { DeviceController.shared.previousTrack() }
        default:
            return nil
        }
    }
}
