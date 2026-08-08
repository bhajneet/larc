import Foundation

/// Every icon in larc, keyed by what it *means* rather than by where it's drawn.
///
/// One concept, one glyph, one place to change it. Before this, optical appeared
/// as `fibrechannel` in two unrelated switches and bluetooth in three, so
/// changing either meant finding all of them — and missing one left the same
/// concept wearing two faces on two screens.
///
/// The rule for adding: name the case after the **concept**, never after the
/// glyph. `.optical`, not `.fibrechannel` — the whole point is that the glyph
/// can change without anything else moving.
///
/// Weights are outlines throughout. A filled glyph among outlines reads as
/// heavier rather than as different, which is why the few remaining `.fill`
/// variants are called out where they appear.
enum LarcIcon {

    // MARK: Inputs

    /// Network streaming — Wi-Fi, AirPlay, Spotify Connect, DLNA.
    static let network = "wifi"
    static let lineIn = "circle.grid.2x1.right.filled"
    static let bluetooth = "suit.diamond"
    /// Optical / TOSLINK / S-PDIF.
    static let optical = "fibrechannel"
    static let hdmi = "tv"
    /// Turntable input.
    static let phono = "opticaldisc"

    // MARK: Outputs

    /// Line-level analogue out.
    static let lineOut = "circle.grid.2x1.right.filled"
    static let coax = "cable.coaxial"
    static let headphones = "headphones"
    /// Powered speaker terminals, on an amplifier. A pair, since the terminals
    /// drive two.
    static let speakers = "hifispeaker.2"
    /// A value the device accepted but larc has no name for.
    static let unknownOutput = "speaker.wave.2"

    // MARK: Channel modes

    /// Two overlapping circles — a family of shapes, not a speaker, so the four
    /// channel modes read as one set.
    static let stereo = "circlebadge.2"
    static let leftOnly = "l.circle"
    static let rightOnly = "r.circle"
    static let mono = "circle"
    /// A channel value this device reports that larc has no name for.
    static let unknownChannel = "questionmark.circle"

    // MARK: Screens and navigation

    static let controls = "point.bottomleft.forward.to.point.topright.scurvepath"
    static let presets = "square.stack.3d.up"
    /// What's queued to play next.
    static let queue = "list.bullet"
    static let about = "info.square"
    static let iconPicker = "paintpalette"
    /// The component gallery. Only reachable in a `--dev` build.
    static let dev = "hammer"
    static let back = "chevron.backward"
    static let disclosure = "chevron.forward"
    static let selected = "checkmark"

    // MARK: Transport
    //
    // The only filled glyphs in the app, deliberately: they're the primary
    // action, and `TrianglePairIcon` builds the skip buttons from `play.fill`
    // so an outline here would break that construction.

    static let play = "play.fill"
    static let pause = "pause.fill"

    // MARK: Device features

    /// A house, not a waveform: the thing being corrected for is the room, and
    /// `waveform` said "audio" — which every icon on that screen already says.
    static let roomCorrection = "music.note.house"
    /// Room correction switched off — the choice, not the absence of one.
    static let roomCorrectionOff = "slash.circle"
    /// How far one key press moves the level.
    static let volumeStep = "dial.medium"
    /// A level itself — the slider, and the popover's own volume row.
    static let volume = "speaker.wave.2"

    // MARK: larc's own settings

    static let mediaKeys = "keyboard"
    /// An A inside a circular arrow: "automatically", rather than a power
    /// symbol, which reads as switching the machine off.
    static let launchAtLogin = "autostartstop"
    static let scanNetwork = "network"
    static let quit = "x.square"

    // MARK: Presets

    static let newPreset = "plus.circle"
    static let deletePreset = "trash"
    /// Default glyph for a preset the user hasn't given one to.
    static let presetDefault = "music.note"

    // MARK: About

    static let sourceCode = "chevron.left.forwardslash.chevron.right"
    static let tip = "heart"
    static let diagnostics = "stethoscope"

    // MARK: Status

    static let deviceUnreachable = "wifi.exclamationmark"
    static let warning = "exclamationmark.triangle"
    static let granted = "checkmark.circle.fill"

    // MARK: Catalogue

    /// Every icon, grouped, for the Dev screen.
    ///
    /// Listed by hand because Swift can't enumerate static properties — so the
    /// one rule when adding an icon is to add it here too. That's the cost of
    /// the gallery being able to show *everything*; a gallery that silently
    /// omits new icons is worse than none, since it would be trusted.
    static let catalogue: [(group: String, items: [(name: String, symbol: String)])] = [
        ("Inputs", [
            ("network", network), ("lineIn", lineIn), ("bluetooth", bluetooth),
            ("optical", optical), ("hdmi", hdmi), ("phono", phono),
        ]),
        ("Outputs", [
            ("lineOut", lineOut), ("coax", coax), ("headphones", headphones),
            ("speakers", speakers), ("unknownOutput", unknownOutput),
        ]),
        ("Channels", [
            ("stereo", stereo), ("leftOnly", leftOnly), ("rightOnly", rightOnly),
            ("mono", mono), ("unknownChannel", unknownChannel),
        ]),
        ("Screens", [
            ("controls", controls), ("presets", presets), ("about", about),
            ("queue", queue),
            ("iconPicker", iconPicker), ("back", back),
            ("disclosure", disclosure), ("selected", selected),
        ]),
        ("Transport", [("play", play), ("pause", pause)]),
        ("Device features", [
            ("roomCorrection", roomCorrection),
            ("roomCorrectionOff", roomCorrectionOff),
            ("volumeStep", volumeStep), ("volume", volume),
        ]),
        ("larc settings", [
            ("mediaKeys", mediaKeys), ("launchAtLogin", launchAtLogin),
            ("scanNetwork", scanNetwork), ("quit", quit),
        ]),
        ("Presets", [
            ("newPreset", newPreset), ("deletePreset", deletePreset),
            ("presetDefault", presetDefault),
        ]),
        ("About", [
            ("sourceCode", sourceCode), ("tip", tip),
            ("diagnostics", diagnostics),
        ]),
        ("Status", [
            ("deviceUnreachable", deviceUnreachable), ("warning", warning),
            ("granted", granted),
        ]),
    ]

    /// Flat list, for handing sample components a different icon each.
    static var allSymbols: [String] {
        catalogue.flatMap { $0.items.map(\.symbol) }
    }
}
