import Foundation

enum DeviceSource: String, Codable {
    case discovered
    case manual
}

/// Which protocol family a device speaks. Only Linkplay for now; BluOS,
/// MusicCast and HEOS are planned (see README roadmap).
enum DeviceKind: String, Codable, CaseIterable, Identifiable {
    case linkplay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .linkplay: return "WiiM / Linkplay"
        }
    }
}

struct AudioDevice: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var host: String
    var source: DeviceSource
    var kind: DeviceKind

    init(id: String, name: String, host: String, source: DeviceSource, kind: DeviceKind = .linkplay) {
        self.id = id
        self.name = name
        self.host = host
        self.source = source
        self.kind = kind
    }

    // Manual devices saved by v0.1.0 predate `kind`; default them to Linkplay.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        source = try container.decode(DeviceSource.self, forKey: .source)
        kind = try container.decodeIfPresent(DeviceKind.self, forKey: .kind) ?? .linkplay
    }
}

enum PlayState: Equatable {
    case playing
    case paused
    case stopped
    case loading
    case unknown

    /// Whether the transport should *read* as playing.
    ///
    /// `.loading` counts. Linkplay reports `status: "load"` while a device
    /// buffers the next track, and drawing the play glyph for it made the
    /// play/pause icon flip twice on every track change — to play while
    /// loading, then back to pause once audio started. A loading device is on
    /// its way to playing, so showing pause is the honest reading.
    var showsAsPlaying: Bool {
        self == .playing || self == .loading
    }

    /// Whether a polled value is a settled answer rather than a device caught
    /// mid-move. Used by `DeviceController.apply(_:)`: within the transport
    /// guard window an unsettled report is ignored in favour of the local state,
    /// while a settled one is accepted at once.
    ///
    /// `.stopped` counts as **unsettled**, deliberately. It's what a device
    /// reports both in the gap during a track change and at the end of a queue,
    /// and a single sample can't distinguish those — so it has to be held long
    /// enough for a real track change to complete.
    var isSettled: Bool {
        self == .playing || self == .paused
    }
}

extension Optional where Wrapped == String {
    /// Nil for nil, empty, or whitespace-only — so `?? fallback` chains treat
    /// a blank field the same as a missing one.
    var nonEmpty: String? {
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

struct PlayerStatus: Equatable {
    var volume: Int
    var muted: Bool
    var state: PlayState
    var title: String?
    var artist: String?
    var album: String?
    /// Cover art for the current track. Nil whenever the source doesn't
    /// provide one — plenty don't, so the UI always needs a placeholder.
    var albumArtURL: URL?
    /// Whatever the source itself called a "subtitle", distinct from the
    /// `subtitle` line this type composes below. Radio stations put the station
    /// name here ("CNN") while leaving artist and album as placeholders, so it's
    /// the only thing available for those.
    var sourceSubtitle: String?
    /// Seconds. Nil for a source that doesn't report them — a live radio stream
    /// has a position but no length, so the two are separately optional and a
    /// seek bar needs both before it can draw.
    var position: Double?
    var duration: Double?
    /// Which physical input the device is on, from `getPlayerStatus.mode` —
    /// already in the poll, so this costs nothing.
    ///
    /// Nil for network playback and for modes we haven't mapped. **That nil is
    /// the useful case**: it means the device is the source and therefore knows
    /// what's playing.
    var input: AudioInput?

    /// True when the device is passing through an external source and can't see
    /// into it.
    ///
    /// On optical or HDMI the WiiM has audio but no idea what it is — no title,
    /// no artist, no position, and often a stale copy of whatever it played last
    /// over the network. So the popover shows the input's name instead of
    /// presenting old metadata as though it were current.
    var isExternalSource: Bool {
        guard let input else { return false }
        return input != .network
    }

    /// Whether the device can drive playback on this input at all.
    ///
    /// Analogue and S/PDIF passthrough have no stream to control — there is
    /// nothing for play/pause to act on, so the buttons could only ever do
    /// nothing. Wi-Fi is the device's own player; Bluetooth relays to the phone
    /// over AVRCP; HDMI reaches the TV over CEC (tested working on the Ultra).
    ///
    /// **Note `isExternalSource` is not the same question** and can't be reused
    /// here: it groups Bluetooth and HDMI with optical, which is right for
    /// metadata and seeking and wrong for transport.
    ///
    /// An unrecognised mode returns true — AirPlay and Spotify Connect arrive as
    /// their own numbers and do take transport, so the default has to be to
    /// offer rather than to withhold.
    var supportsTransport: Bool { input?.supportsTransport ?? true }

    /// Whether this track can be scrubbed: it has to have a length, and one long
    /// enough to be worth a bar. A live stream reports a growing position against
    /// no total, which would otherwise draw a bar that only ever fills.
    var isSeekable: Bool {
        // An external source rules it out regardless of what the numbers say:
        // the device reports a position for optical in, and it's meaningless —
        // dragging it does nothing, which is worse than not offering it.
        guard !isExternalSource, let duration else { return false }
        return duration > 1
    }

    /// "Artist • Album", either half omitted if missing, nil if both are.
    /// The popover shows this as the line under the title.
    ///
    /// The album is dropped when it's byte-for-byte identical to the title —
    /// common for singles, where repeating it says nothing. Compared exactly,
    /// not case- or whitespace-insensitively: both fields have already been
    /// trimmed by `LinkplayPlugin.cleaned()`, and a genuine difference in case
    /// is a difference worth showing.
    var subtitle: String? {
        let usefulAlbum = album == title ? nil : album
        let parts = [artist, usefulAlbum].compactMap { $0 }.filter { !$0.isEmpty }
        guard parts.isEmpty else { return parts.joined(separator: " • ") }

        // Nothing usable from artist or album — fall back to the source's own
        // subtitle, which is all radio streams tend to give. Only ever a
        // fallback, never mixed in: when there is an artist, that's the more
        // useful thing to show. Same drop-if-identical-to-title rule as the
        // album, or a station whose title is its own name renders twice.
        return sourceSubtitle == title ? nil : sourceSubtitle
    }
}

/// What a device says it is, asked of the device itself rather than inferred
/// from its name on the network.
///
/// Needed because capability mappings are model-specific: audio output value 2
/// is Line Out on a WiiM Ultra and the speaker terminals on a WiiM Amp. A user's
/// device might be called anything on the network, so the mDNS instance name is
/// useless for this — `LinkplayPlugin` reads `getStatusEx.project`, and a future
/// BluOS backend would read whatever BluOS reports. Each plugin knows how to ask
/// its own hardware; this is the shared shape of the answer.
struct DeviceIdentity: Equatable, Codable {
    /// Protocol family — which plugin is speaking to it.
    var kind: DeviceKind
    /// Manufacturer, where derivable. "WiiM" for a `WiiM_Ultra`.
    var vendor: String?
    /// The device's own model token, verbatim: "WiiM_Ultra", "WiiM_AMP".
    /// **The key for any model-specific capability table** — never prettify it
    /// before using it as one.
    var model: String?
    var firmware: String?

    /// Human-readable, falling back through what's available. Never empty, so
    /// a diagnostics view always has something to show.
    var displayName: String {
        if let model { return model.replacingOccurrences(of: "_", with: " ") }
        if let vendor { return vendor }
        return kind.displayName
    }

    /// Whether larc has verified capability mappings for this exact model.
    /// False means the UI should offer raw values and let the readback decide —
    /// see `AudioOutput.known(for:)`.
    var isMapped: Bool {
        model.map { AudioOutput.mappedModels.contains($0) } ?? false
    }
}

/// A controllable network audio device backend. One implementation per
/// protocol family (Linkplay/WiiM today; BluOS, MusicCast, HEOS later).
protocol DevicePlugin: AnyObject {
    var device: AudioDevice { get }
    /// Asks the hardware what it is. Best-effort: a device that won't say still
    /// controls fine, it just gets generic capability handling.
    /// Nil when the device didn't answer — never a shell identity, which
    /// callers can't tell from a real one.
    func identify() async -> DeviceIdentity?
    func getStatus() async throws -> PlayerStatus
    func setVolume(_ volume: Int) async throws
    func setMute(_ muted: Bool) async throws
    func playPause() async throws
    func next() async throws
    func previous() async throws
}

// MARK: - Room correction

/// A key the room-correction API stores state under — **not** a list of inputs.
///
/// Every correction command requires a `source_name`, and these eight are what
/// it accepts. The names suggest per-input correction, but experiment shows they
/// are not independent settings: writing `default` propagates to six of the
/// others on its own, and `wifi` is inert (setting it alone changed neither the
/// audio nor the vendor app's display, with music playing over the network).
/// Effectively there is **one** setting, reached through `default`.
///
/// The overlap with actual inputs is partial and must not be assumed: `co-axial`
/// is a slot here *and* a physical output on the Ultra, but never an input —
/// `switchmode:co-axial` answers OK and quietly selects optical instead. A UI
/// offering inputs must not be driven from this type.
///
/// Raw values are the exact strings the device expects in `source_name`.
enum AudioSource: String, CaseIterable, Codable, Identifiable, Hashable {
    case wifi
    case `default`
    case lineIn = "line-in"
    case optical
    case bluetooth
    case coaxial = "co-axial"
    case hdmi
    case phono

    var id: String { rawValue }

    /// Matches what a device *reports*, which is not always what it *accepts*.
    ///
    /// The Amp answers `EQGetBand` with `source_name: "HDMI"` while happily
    /// taking `"hdmi"` as an argument, so a plain `init(rawValue:)` returns nil
    /// there and the active-source fast path silently falls back to sweeping all
    /// eight slots. Case-insensitive both ways; raw values stay lowercase
    /// because that is the spelling the device is known to accept.
    init?(deviceValue: String) {
        let normalized = deviceValue.trimmingCharacters(in: .whitespaces).lowercased()
        guard let match = Self.allCases.first(where: { $0.rawValue == normalized })
        else { return nil }
        self = match
    }

    var displayName: String {
        switch self {
        case .wifi: return "Network"
        case .default: return "Default"
        case .lineIn: return "Line In"
        case .optical: return "Optical"
        case .bluetooth: return "Bluetooth"
        case .coaxial: return "Coaxial"
        case .hdmi: return "HDMI"
        case .phono: return "Phono"
        }
    }
}

/// A physical input the device can switch to.
///
/// Separate from `AudioSource` on purpose — that type is room-correction storage
/// keys, and the two lists only partly overlap. `co-axial` is a correction slot
/// and an output jack but never an input; USB is a browsable content source
/// rather than an input mode.
///
/// **`switchmode` is case-sensitive, and `HDMI` is the exception.** Every other
/// name is lowercase. Sixteen lowercase spellings of HDMI were tried and all
/// silently failed; `HDMI` works. Both an Ultra and an Amp report it that way.
///
/// **The device answers `OK` to any spelling, including ones that do nothing** —
/// `switchmode:co-axial` returns OK and selects optical. So a switch is only
/// confirmed by reading the state back, which `LinkplayPlugin.setInput` does.
///
/// Which inputs a given model actually has cannot be queried: no command
/// enumerates them, and `plm_support` is a bitmask whose mapping is unknown
/// (comparing an Ultra to an Amp identifies exactly one bit, probably phono).
/// Rather than guess, offer them and let the verified switch fail.
enum AudioInput: String, CaseIterable, Codable, Identifiable, Hashable {
    case network = "wifi"
    case lineIn = "line-in"
    case bluetooth = "bluetooth"
    case optical = "optical"
    case hdmi = "HDMI"
    case phono = "phono"

    var id: String { rawValue }

    /// What `getPlayerStatus.mode` reports for this input — the device's own
    /// numeric vocabulary, which `switchmode` does not accept. Verified on a
    /// WiiM Ultra; HDMI 49 also confirmed on an Amp.
    var mode: Int {
        switch self {
        case .network: return 10
        case .lineIn: return 40
        case .bluetooth: return 41
        case .optical: return 43
        case .hdmi: return 49
        case .phono: return 54
        }
    }

    /// Whether play/pause and skip mean anything on this input.
    ///
    /// False for the passthrough inputs, where there is no stream to act on.
    /// The device does answer transport there — on optical `onepause` toggles
    /// its own output gate — but the source keeps running, so the audio simply
    /// vanishes while whatever is feeding the cable plays on. That is not what
    /// anyone pressing pause meant.
    ///
    /// Bluetooth and HDMI are true, both tested: Bluetooth relays over AVRCP and
    /// HDMI reaches the TV over CEC.
    var supportsTransport: Bool {
        switch self {
        case .network, .bluetooth, .hdmi: return true
        case .lineIn, .optical, .phono: return false
        }
    }

    /// Resolves `getPlayerStatus.mode`, which conflates two things: which
    /// physical input is selected, and what is playing through it.
    ///
    /// - A **negative** mode means idle — a WiiM with nothing playing reports
    ///   `mode: -1, status: none` regardless of which input is selected. That is
    ///   not an input, so it returns nil and callers hold whatever they had:
    ///   pressing stop does not unplug the optical cable.
    /// - An **unrecognised non-negative** mode is `.network`. The passthrough
    ///   inputs are a short enumerable set with fixed numbers; everything else
    ///   the device can play — AirPlay, Spotify Connect, DLNA, its own queue —
    ///   arrives over the network under its own number. Guessing `.network` is
    ///   right for all of them, where nil drew no selection at all and made a
    ///   working device look unreadable.
    init?(mode: Int) {
        if let match = Self.allCases.first(where: { $0.mode == mode }) {
            self = match
        } else if mode < 0 {
            return nil
        } else {
            self = .network
        }
    }

    /// Case-insensitive, since devices report mixed case regardless of what
    /// they accept.
    init?(deviceValue: String) {
        let normalized = deviceValue.trimmingCharacters(in: .whitespaces).lowercased()
        guard let match = Self.allCases.first(
            where: { $0.rawValue.lowercased() == normalized }
        ) else { return nil }
        self = match
    }

    /// Short enough for a 48pt tile — four across the popover's 210pt content
    /// width. Measured at 9pt against a 44pt budget: "HDMI ARC" was 45.7 and
    /// "Bluetooth" 42.5, the second of which fit by 1.5pt and so had no margin
    /// for a wider system font. Both are shortened; the glyph above carries the
    /// distinction the dropped words were making.
    var displayName: String {
        switch self {
        case .network: return "Wi-Fi"
        case .lineIn: return "Line In"
        case .bluetooth: return "BT"
        case .optical: return "Optical"
        case .hdmi: return "HDMI"
        case .phono: return "Phono"
        }
    }

    /// Chosen from symbols that have existed since macOS 11, so the deployment
    /// target can't render an empty box for one of them.
    var symbolName: String {
        switch self {
        case .network: return LarcIcon.network
        case .lineIn: return LarcIcon.lineIn
        case .bluetooth: return LarcIcon.bluetooth
        case .optical: return LarcIcon.optical
        case .hdmi: return LarcIcon.hdmi
        case .phono: return LarcIcon.phono
        }
    }
}

/// Which physical output the device sends audio to.
///
/// Like `ChannelMode`, a **raw integer with a labelling** rather than an enum:
/// nothing on the device enumerates the valid values, so an unrecognised one
/// must still round-trip and display rather than be dropped.
///
/// Values verified by ear on a WiiM Ultra and cross-checked against the WiiM app's
/// own Audio Output screen, whose labels these reproduce exactly. Note the app
/// lists them in a different order than their numeric values, so **UI order is
/// not value order** — don't infer one from the other.
///
/// `0` and `5`–`7` were refused (the device answered `OK` and kept its previous
/// value — `OK` means nothing here either). The app also offers **Bluetooth Out**
/// and **DLNA Out**, both showing "Not Paired", which is the likely reason two of
/// the refused values exist but won't take. Unproven: pair a device and re-sweep.
///
/// **Ultra-only.** The Amp reports `hardware: 2` but has speakers and no
/// headphone jack, so its mapping is almost certainly different and is unverified.
struct AudioOutput: Equatable, Hashable, Codable, Identifiable {
    let rawValue: Int
    /// `getStatusEx.project` — "WiiM_Ultra", "WiiM_AMP". **The same number means
    /// different outputs on different models**, so a value without a model is
    /// only a number.
    let model: String?

    init(_ rawValue: Int, model: String? = nil) {
        self.rawValue = rawValue
        self.model = model
    }

    var id: Int { rawValue }

    /// Per-model, because value 2 is Line Out on an Ultra and the speaker
    /// terminals on an Amp — verified by ear on both, and matching each app's
    /// own Audio Output screen.
    ///
    /// Labels are shorter than the vendor's ("Optical Out", "COAX Out",
    /// "Headphone Out"): a picker already in an output context needn't repeat
    /// the word on every row. "Line Out" keeps its suffix because "Line" alone
    /// names a direction rather than the jack.
    /// Models with verified mappings. `DeviceIdentity.isMapped` reads this, so
    /// adding a model in one place makes the whole UI treat it as known.
    static var mappedModels: Set<String> { Set(labelsByModel.keys) }

    private static let labelsByModel: [String: [Int: String]] = [
        // "Phones" rather than "Headphones": 55.2pt at 9pt against a 44pt tile.
        "WiiM_Ultra": [1: "Optical", 2: "Line Out", 3: "Coax", 4: "Phones"],
        // The Amp accepts only 2. Its app offers Speaker Out and an unpaired
        // Bluetooth Out, so a second value likely exists once Bluetooth is
        // paired — untested.
        "WiiM_AMP": [2: "Speakers"],
    ]

    private var labels: [Int: String] {
        model.flatMap { Self.labelsByModel[$0] } ?? [:]
    }

    /// Values to offer for a model, best source first.
    ///
    /// 1. **Values this device accepted during a discovery run**, remembered per
    ///    model. Exactly right, because the hardware said so.
    /// 2. The built-in table, for models verified during development.
    /// 3. **1–6 unlabelled**, for anything else.
    ///
    /// The fallback offers values that may not work, and it has to: nothing on
    /// the device reports which outputs exist, so the only way to find out is to
    /// try them — which moves the audio and can't be done silently. A refused
    /// value is harmless (`setAudioOutput` catches it by readback and throws),
    /// so offering the range beats offering nothing on hardware we've never
    /// seen. Run `discoverOutputs()` once and this collapses to case 1.
    /// **A refused value is kept, not dropped.** It's flagged instead — see
    /// `wasRefused` — and stays selectable.
    ///
    /// Removing it was worse than it sounds. A refusal can be wrong: the
    /// readback used to race the device, so picking an output that plainly
    /// worked could still record a refusal, and the tile then vanished with no
    /// way to try again. Even a *correct* refusal can go stale — a firmware
    /// update adds an output, a Bluetooth speaker gets paired — and a value
    /// nobody can select is a value that can never prove itself right again.
    /// A warning says the same thing without being a dead end.
    static func known(for model: String?) -> [AudioOutput] {
        if let model {
            // Union of what we know, what this device has confirmed, and what
            // it has refused — all three are values worth showing.
            //
            // Not "discovered first": simply reading the current output records
            // it as accepted, so a mapped device would collapse to the single
            // output it happened to be set to — an Ultra showed Line Out alone
            // and nothing else. Observation should add to the table, never
            // replace it.
            let table = Set(labelsByModel[model]?.keys ?? [:].keys)
            let confirmed = Set(discovered(for: model) ?? [])
            let denied = Set(refused(for: model))
            let values = table.union(confirmed).union(denied)
            if !values.isEmpty {
                return values.sorted().map { AudioOutput($0, model: model) }
            }
        }
        return (1...6).map { AudioOutput($0, model: model) }
    }

    /// This device has refused this value before, so it probably isn't a jack
    /// this hardware has — but it stays offered, because "probably" is as far as
    /// a readback can get and the alternative is a list that only ever shrinks.
    var wasRefused: Bool {
        model.map { Self.refused(for: $0).contains(rawValue) } ?? false
    }

    /// Remembered per model rather than per device: two Ultras have the same
    /// outputs, so learning on one answers for both.
    private static let discoveredKey = "discoveredOutputsByModel"
    private static let refusedKey = "refusedOutputsByModel"

    static func discovered(for model: String) -> [Int]? {
        UserDefaults.standard.dictionary(forKey: discoveredKey)?[model] as? [Int]
    }

    static func refused(for model: String) -> [Int] {
        UserDefaults.standard.dictionary(forKey: refusedKey)?[model] as? [Int] ?? []
    }

    /// Records what happened when a value was actually selected.
    ///
    /// **This is how the list gets right without a disruptive sweep.** Every
    /// `setAudioOutput` verifies by readback anyway, so each pick the user makes
    /// is already an experiment — one that costs nothing extra because they
    /// wanted the switch regardless. A value that sticks is real; one that
    /// silently doesn't never needs offering again.
    static func record(_ value: Int, accepted: Bool, for model: String) {
        let key = accepted ? discoveredKey : refusedKey
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        var values = Set(all[model] as? [Int] ?? [])
        values.insert(value)
        all[model] = values.sorted()
        UserDefaults.standard.set(all, forKey: key)

        // A value can't be in both. Firmware updates do add outputs, so let the
        // newer observation win rather than treating the first as permanent.
        let otherKey = accepted ? refusedKey : discoveredKey
        var others = UserDefaults.standard.dictionary(forKey: otherKey) ?? [:]
        if var stale = others[model] as? [Int], stale.contains(value) {
            stale.removeAll { $0 == value }
            others[model] = stale
            UserDefaults.standard.set(others, forKey: otherKey)
        }
    }

    static func recordDiscovered(_ values: [Int], for model: String) {
        for value in values { record(value, accepted: true, for: model) }
    }

    /// Whether this model's list came from the device rather than a table or the
    /// fallback — the difference between "these are your outputs" and "try these
    /// and see".
    static func isDiscovered(_ model: String?) -> Bool {
        model.flatMap { discovered(for: $0) }?.isEmpty == false
    }

    /// The label where we have one, the bare number where we don't — never both.
    /// "Line Out" reads as a name; "2" reads as a value to identify by trying;
    /// "2 · Line Out" just makes a picker noisy once the label is trustworthy.
    var displayName: String {
        labels[rawValue] ?? "\(rawValue)"
    }

    var shortName: String { displayName }

    /// Derived from the label rather than the value, because the same number is
    /// a different jack on different models — so matching on "Optical" is
    /// correct where matching on `1` would be wrong on hardware we haven't
    /// mapped. Unlabelled values get a neutral glyph.
    var symbolName: String {
        let name = (labels[rawValue] ?? "").lowercased()
        if name.contains("optical") { return LarcIcon.optical }
        if name.contains("coax") { return LarcIcon.coax }
        if name.contains("head") { return LarcIcon.headphones }
        if name.contains("phone") { return LarcIcon.headphones }
        if name.contains("jack") { return LarcIcon.headphones }
        if name.contains("speaker") { return LarcIcon.speakers }
        if name.contains("line") { return LarcIcon.lineOut }
        if name.contains("blue") { return LarcIcon.bluetooth }
        return LarcIcon.unknownOutput
    }

    var isNamed: Bool { labels[rawValue] != nil }
}

/// How the device folds its two channels on output.
///
/// **This is a raw integer with a *labelling*, not an enum, and the distinction
/// is deliberate.** `getChannelMode` returns a bare number; nothing on the
/// device enumerates the valid set or says what any value means. The labels
/// below were established by listening on one WiiM Ultra
/// (`tools/audio-experiment.py channel`) and are therefore an **observation
/// that can go stale** — a different model could order them differently, and a
/// firmware update could insert a value.
///
/// So the raw value is what's stored and sent, and an unrecognised one renders
/// as "Mode 5" rather than being dropped or, worse, mislabelled. A device that
/// grows a fifth mode stays usable; it just isn't named until someone listens.
///
/// If the labels ever need re-verifying, `audio_channel_config` in `getStatusEx`
/// is a version string (`"1.0"` on both an Ultra and an Amp today) and is the
/// natural drift signal to watch.
struct ChannelMode: Equatable, Hashable, Codable, Identifiable {
    let rawValue: Int

    init(_ rawValue: Int) { self.rawValue = rawValue }

    var id: Int { rawValue }

    /// Verified by ear on a WiiM Ultra, firmware Linkplay.5.2.818432.
    private static let observedLabels: [Int: String] = [
        0: "Stereo", 1: "Left", 2: "Right", 3: "Mono",
    ]

    /// The modes we can name. A picker should offer these *plus* the current
    /// value if it isn't among them, so an unknown mode is never silently
    /// changed just by opening the menu.
    static let known: [ChannelMode] = observedLabels.keys.sorted().map(ChannelMode.init)

    static let stereo = ChannelMode(0)

    /// The label where we have one, the bare number where we don't — never both.
    /// An unidentified mode stays selectable rather than invisible.
    var displayName: String {
        Self.observedLabels[rawValue] ?? "\(rawValue)"
    }

    var shortName: String { displayName }

    /// Shapes rather than speakers, so the four read as one family: two
    /// overlapping circles for stereo, letters for the single channels, one
    /// filled circle for mono. A speaker glyph for stereo looked like a volume
    /// control sitting among three shape icons.
    var symbolName: String {
        switch rawValue {
        case 0: return LarcIcon.stereo
        case 1: return LarcIcon.leftOnly
        case 2: return LarcIcon.rightOnly
        case 3: return LarcIcon.mono
        default: return LarcIcon.unknownChannel
        }
    }

    /// False when this device reports something outside what we've verified —
    /// worth surfacing rather than hiding, since it means the mapping needs
    /// re-checking on that hardware.
    var isNamed: Bool { Self.observedLabels[rawValue] != nil }
}

/// A stored room-correction ("RoomFit") profile.
///
/// Created by the vendor's app using the phone's microphone — larc can list,
/// read and select them, but not create them.
struct RoomFitProfile: Identifiable, Equatable, Hashable {
    var name: String
    /// "Stereo" (one curve) or "L/R" (independent per-channel curves).
    var channelMode: String
    /// Which physical output the measurement was taken on, e.g.
    /// `AUDIO_OUTPUT_PHONE_JACK_MODE`. **Metadata only** — a profile applies
    /// regardless of the current output, verified by ear. Not a constraint.
    var calibratedOutput: String?

    var id: String { name }

    var isPerChannel: Bool { channelMode == "L/R" }
}

/// What a given source's correction slot currently holds.
struct RoomFitState: Equatable {
    /// Empty when a profile's filter is loaded but nothing recorded which one —
    /// the state `EQv2Load` alone leaves behind. See `LinkplayPlugin`.
    var profileName: String
    var enabled: Bool
    var channelMode: String

    var profile: String? { profileName.isEmpty ? nil : profileName }

    /// What a picker should show as selected.
    ///
    /// A disabled slot still remembers its profile name, so turning correction
    /// off and on again restores the same profile rather than losing it — which
    /// is why `enabled` is checked before the name, not instead of it.
    func selection(among profiles: [RoomFitProfile]) -> RoomFitSelection {
        guard enabled, let name = profile,
              let match = profiles.first(where: { $0.name == name })
        else { return .off }
        return .profile(match)
    }
}

/// A room-correction choice as the UI presents it: one list containing every
/// stored profile plus "None".
///
/// "None" is a real choice rather than the absence of one — the device keeps
/// correction enabled or disabled independently of which profile is named, so
/// the two have to be set together or the UI drifts from the hardware. Selecting
/// a profile must also *enable* correction, which is what
/// `LinkplayPlugin.setRoomFit` guarantees.
enum RoomFitSelection: Equatable, Hashable, Identifiable {
    case off
    case profile(RoomFitProfile)

    var id: String {
        switch self {
        case .off: return "\u{0}none"   // can't collide with a profile name
        case .profile(let profile): return profile.name
        }
    }

    var displayName: String {
        switch self {
        case .off: return "None"
        case .profile(let profile): return profile.name
        }
    }

    /// Name with the channel mode in parentheses — "desktop edifiers (L/R)".
    /// A menu row has one line, so the mode has to share it or be lost, and it
    /// is the thing that distinguishes two similarly-named profiles.
    var menuLabel: String {
        guard let mode = channelMode else { return displayName }
        return "\(displayName) (\(mode))"
    }

    /// "Stereo" / "L/R" for a profile, nil for None — a secondary line in a
    /// picker row, and the value the device needs when selecting.
    var channelMode: String? {
        switch self {
        case .off: return nil
        case .profile(let profile): return profile.channelMode
        }
    }
}

/// Room correction, kept **out** of `DevicePlugin` deliberately: it's specific
/// to hardware that has it, and a future BluOS or HEOS backend shouldn't be
/// forced to stub it out. Call sites test with `as? RoomCorrecting`.
protocol RoomCorrecting: AnyObject {
    /// Profiles stored on the device, in the order it lists them.
    func roomFitProfiles() async throws -> [RoomFitProfile]
    /// The source the device is currently playing from, so a caller can scope a
    /// read or a write to it instead of touching all eight.
    func activeSource() async throws -> AudioSource?
    func roomFitState(source: AudioSource) async throws -> RoomFitState
    /// Applies a selection, profile **and** on/off together.
    ///
    /// One call rather than two because the device stores the profile name and
    /// the enabled flag in the same record: setting them separately would leave
    /// a window where correction is named but off, which is exactly the state
    /// that made the vendor app look broken during development.
    func setRoomFit(_ selection: RoomFitSelection) async throws
}

/// Volume step, stored **per device**.
///
/// It was one global number, but the step that suits a pair of desktop speakers
/// is not the step that suits an amplifier driving a room — and larc can be
/// pointed at either from the same menu. Keyed by the device's stable mDNS uuid,
/// so it follows the hardware rather than the network address.
///
/// Falls back to the global value, which is what every existing install has, so
/// nobody's setting is lost by this becoming per-device.
enum VolumeStepStore {
    static let options = [1, 2, 3, 4, 5, 6, 8]
    /// 4 for a device we haven't seen before. Small enough to be precise,
    /// large enough that reaching a comfortable level doesn't take a dozen
    /// presses.
    static let fallback = 4

    private static let key = "volumeStepByDevice"

    static func step(for deviceID: String?) -> Int {
        if let deviceID,
           let all = UserDefaults.standard.dictionary(forKey: key),
           let value = all[deviceID] as? Int, value > 0 {
            return value
        }
        let global = UserDefaults.standard.integer(forKey: SettingsKeys.volumeStep)
        return global > 0 ? global : fallback
    }

    static func setStep(_ value: Int, for deviceID: String?) {
        guard let deviceID else {
            UserDefaults.standard.set(value, forKey: SettingsKeys.volumeStep)
            return
        }
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        all[deviceID] = value
        UserDefaults.standard.set(all, forKey: key)
    }
}

enum SettingsKeys {
    /// All-or-nothing: when on (and Accessibility is granted), all six media
    /// keys — volume up/down/mute and play/next/previous — go to the device.
    static let mediaKeysEnabled = "mediaKeysEnabled"
    static let volumeStep = "volumeStep"
    /// JSON-encoded [gatewayMAC: deviceID] — remembers which device was
    /// selected on each network (see NetworkFingerprint), so switching
    /// networks doesn't carry a stale selection over.
    static let perNetworkDeviceID = "perNetworkDeviceID"
    static let manualDevices = "manualDevices"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"

    static let defaults: [String: Any] = [
        mediaKeysEnabled: false,
        volumeStep: 3,
        hasCompletedOnboarding: false,
    ]
}
