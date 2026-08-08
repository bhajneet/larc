import Foundation

/// Controls a WiiM / Linkplay device via its local HTTP API:
/// `http(s)://<host>/httpapi.asp?command=<cmd>`.
///
/// HTTPS is tried first (WiiM devices advertise `security: https 3.0` and use a
/// self-signed certificate, which is accepted for this device's host only);
/// plain HTTP on port 80 is the fallback for older Linkplay firmware.
final class LinkplayPlugin: DevicePlugin {

    enum LinkplayError: LocalizedError {
        case badURL
        case badResponse

        var errorDescription: String? {
            switch self {
            case .badURL: return "Could not build device URL."
            case .badResponse: return "Device returned an unexpected response."
            }
        }
    }

    let device: AudioDevice
    private var scheme: String?
    private var cachedModel: String?
    /// `max_volume` from `getStatusEx`. 100 until identification says otherwise,
    /// since that's what every device without a cap reports.
    private(set) var cachedMaxVolume = 100
    private let session: URLSession

    init(device: AudioDevice) {
        self.device = device
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 6
        session = URLSession(
            configuration: config,
            delegate: SelfSignedTrustDelegate(host: device.host),
            delegateQueue: nil
        )
    }

    deinit {
        session.invalidateAndCancel()
    }

    // MARK: - DevicePlugin

    /// Reads `getStatusEx`, which reports the model as `project` — "WiiM_Ultra",
    /// "WiiM_AMP". That's firmware-reported and independent of whatever the
    /// device is called on the network, so it identifies hardware the user
    /// renamed, and hardware neither of us has seen.
    ///
    /// Never throws: identification is a nicety, and a device that won't answer
    /// still plays music. It just falls back to generic capability handling.
    /// Nil when the device didn't answer.
    ///
    /// **Optional deliberately.** This used to return an identity with every
    /// field nil on failure, which is indistinguishable from a device that
    /// answered without naming itself — so callers read "identified" and asked
    /// `AudioOutput.known(nil)`, which falls back to six unlabelled numbers.
    /// A first open of Controls could therefore show jacks the hardware doesn't
    /// have and never correct itself, because nothing knew to retry.
    func identify() async -> DeviceIdentity? {
        guard let data = try? await send("getStatusEx"),
              let raw = try? JSONDecoder().decode(RawStatusEx.self, from: data)
        else { return nil }
        if let project = raw.project { cachedModel = project }
        if let cap = raw.max_volume.flatMap(Int.init), cap > 0 {
            cachedMaxVolume = cap
        }
        return DeviceIdentity(
            kind: .linkplay,
            // "WiiM_Ultra" -> "WiiM". Only split on the separator the models
            // actually use; anything else is passed through whole rather than
            // guessed at.
            vendor: raw.project?.split(separator: "_").first.map(String.init),
            model: raw.project,
            firmware: raw.firmware
        )
    }

    func getStatus() async throws -> PlayerStatus {
        // Two endpoints, fetched concurrently. getPlayerStatus is the source of
        // truth for volume/mute/transport; getMetaInfo carries the artwork URL
        // and cleaner text, but is WiiM-specific and absent on other Linkplay
        // hardware — so it's best-effort and never fails the whole poll.
        async let statusData = send("getPlayerStatus")
        async let meta = metaInfo()

        let raw = try JSONDecoder().decode(RawPlayerStatus.self, from: await statusData)
        let metaData = await meta

        let state: PlayState
        switch raw.status {
        case "play": state = .playing
        case "pause": state = .paused
        case "stop": state = .stopped
        case "load": state = .loading
        default: state = .unknown
        }

        // getMetaInfo's text wins when present — it arrives as plain UTF-8,
        // where getPlayerStatus hex-encodes and occasionally mangles it. Falls
        // back field by field rather than all-or-nothing, since a source can
        // populate some and not others.
        return PlayerStatus(
            volume: min(100, max(0, Int(raw.vol ?? "") ?? 0)),
            muted: raw.mute == "1",
            state: state,
            // Both paths unescape: getMetaInfo's text is plain UTF-8 rather than
            // hex, but it comes from the same DIDL-Lite source and carries the
            // same entities.
            title: Self.cleaned(metaData?.title).map(Self.unescapedEntities)
                ?? Self.decodeMetadataField(raw.Title),
            artist: Self.cleaned(metaData?.artist).map(Self.unescapedEntities)
                ?? Self.decodeMetadataField(raw.Artist),
            album: Self.cleaned(metaData?.album).map(Self.unescapedEntities)
                ?? Self.decodeMetadataField(raw.Album),
            // Requires a scheme: URL(string:) happily accepts "unknow" as a
            // relative URL, which would then fail to load as a silent blank.
            albumArtURL: Self.cleaned(metaData?.albumArtURI)
                .flatMap(URL.init(string:))
                .flatMap { $0.scheme == nil ? nil : $0 },
            // Only reaches the UI when artist and album are both unusable —
            // see PlayerStatus.subtitle.
            sourceSubtitle: Self.cleaned(metaData?.subtitle).map(Self.unescapedEntities),
            // Milliseconds on the wire. Already in the poll we make, so a seek
            // bar costs no extra request.
            position: raw.curpos.flatMap(Double.init).map { $0 / 1000 },
            duration: raw.totlen.flatMap(Double.init).map { $0 / 1000 },
            input: Int(raw.mode ?? "").flatMap(AudioInput.init(mode:))
        )
    }

    /// `getMetaInfo` (lowercase g — `GetMetaInfo` is "unknown command"),
    /// confirmed working on WiiM hardware. Returns nil rather than throwing:
    /// the command doesn't exist on every Linkplay device, and losing artwork
    /// must never cost us volume and transport state.
    private func metaInfo() async -> RawMetaData? {
        guard let data = try? await send("getMetaInfo") else { return nil }
        return try? JSONDecoder().decode(RawMetaInfo.self, from: data).metaData
    }

    func setVolume(_ volume: Int) async throws {
        let clamped = min(100, max(0, volume))
        _ = try await send("setPlayerCmd:vol:\(clamped)")
    }

    func setMute(_ muted: Bool) async throws {
        _ = try await send("setPlayerCmd:mute:\(muted ? 1 : 0)")
    }

    /// Jumps to a position, in seconds.
    ///
    /// Not verified by readback like the settings setters: position moves on its
    /// own, so re-reading proves nothing — by the time the answer arrives the
    /// value has legitimately changed. The next poll shows where it landed.
    func seek(to seconds: Double) async throws {
        _ = try await send("setPlayerCmd:seek:\(Int(seconds.rounded()))")
    }

    func playPause() async throws {
        _ = try await send("setPlayerCmd:onepause")
    }

    func next() async throws {
        _ = try await send("setPlayerCmd:next")
    }

    func previous() async throws {
        _ = try await send("setPlayerCmd:prev")
    }

    // MARK: - Input switching

    /// The input the device is currently on, from `getPlayerStatus.mode`.
    ///
    /// Returns nil for a mode we haven't mapped rather than guessing — AirPlay
    /// and Spotify Connect arrive as their own mode numbers and aren't physical
    /// inputs.
    func currentInput() async throws -> AudioInput? {
        let data = try await send("getPlayerStatus")
        let raw = try JSONDecoder().decode(RawPlayerStatus.self, from: data)
        return Int(raw.mode ?? "").flatMap(AudioInput.init(mode:))
    }

    /// Switches input, **verifying by readback**.
    ///
    /// The device returns `OK` for any spelling, including ones that do nothing:
    /// `switchmode:co-axial` answers OK and quietly selects optical, and sixteen
    /// wrong spellings of HDMI all answered OK while staying on Wi-Fi. So the
    /// reply is worthless as a success signal and the state has to be re-read.
    ///
    /// Throwing on a failed switch is also how larc copes with not being able to
    /// enumerate a model's inputs: offer them all, and let the ones the hardware
    /// lacks fail honestly instead of appearing to work.
    func setInput(_ input: AudioInput) async throws {
        _ = try await send("setPlayerCmd:switchmode:\(input.rawValue)")
        guard await confirm({ try await self.currentInput() == input }) else {
            throw LinkplayError.badResponse
        }
    }

    /// Reads a value back until it matches, or gives up.
    ///
    /// **A single immediate readback is not enough.** `OK` means nothing on this
    /// hardware — that's why every setter verifies — but the change also isn't
    /// always *applied* by the time the reply arrives. Reading straight back
    /// returns the previous value and the write looks refused when it plainly
    /// worked: picking Line Out on an Ultra switched the device, then reported
    /// "This device refused that output", reverted the UI, and wrote value 2 to
    /// the refused list so the tile disappeared entirely.
    ///
    /// First attempt immediate, so a device that applies synchronously costs
    /// nothing. Twenty-four more at 250ms — six seconds — for one that doesn't.
    ///
    /// **Long, deliberately.** The two outcomes are not symmetric: waiting
    /// longer than necessary costs a moment on a change that has already
    /// happened, while giving up early costs a written-down refusal that
    /// removes a real output from the picker until the device happens to report
    /// it again. Six seconds of patience is cheap against that.
    private func confirm(
        _ matches: () async throws -> Bool,
        attempts: Int = 25,
        interval: TimeInterval = 0.25
    ) async -> Bool {
        for attempt in 0..<attempts {
            if attempt > 0 {
                try? await Task.sleep(
                    nanoseconds: UInt64(interval * 1_000_000_000)
                )
            }
            if let matched = try? await matches(), matched { return true }
        }
        return false
    }

    // MARK: - Channel mode

    /// Stereo / left / right / mono. Unpublished, like most of this API —
    /// `getChannelMode` returns a bare integer and `setChannelMode` was
    /// confirmed by writing back the value the getter already reported, which
    /// is a no-op if the command exists and `unknown command` if it doesn't.
    /// Returns whatever the device reports, named or not — a value we haven't
    /// verified by ear still round-trips correctly and displays as "Mode N".
    func channelMode() async throws -> ChannelMode? {
        let data = try await send("getChannelMode")
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let value = Int(text) else { return nil }
        return ChannelMode(value)
    }

    func setChannelMode(_ mode: ChannelMode) async throws {
        _ = try await send("setChannelMode:\(mode.rawValue)")
        // **Verified, like every other setter.** This one sent and returned,
        // so a refused mode failed silently — the opposite of the output bug,
        // and worse: nothing on screen ever said the change hadn't happened.
        guard await confirm({ try await self.channelMode()?.rawValue == mode.rawValue })
        else { throw LinkplayError.badResponse }
    }

    // MARK: - Output routing

    /// Note the getter carries `New` and the setter does not — the names are not
    /// symmetric, and guessing `setNewAudioOutputHardwareMode` returns
    /// `unknown command`.
    func audioOutput() async throws -> AudioOutput? {
        async let modeData = send("getNewAudioOutputHardwareMode")
        async let model = deviceModel()
        let raw = try JSONDecoder().decode(RawOutputMode.self, from: await modeData)
        guard let value = Int(raw.hardware ?? "") else { return nil }
        let identifiedModel = await model
        // Whatever the device is currently set to is, by definition, a value it
        // accepts — so simply reading it teaches us one real output at zero
        // cost, and it's the one this user actually listens on. That means even
        // a never-before-seen model has one confirmed entry from the first poll,
        // before anyone has picked anything or run a sweep.
        if let identifiedModel {
            AudioOutput.record(value, accepted: true, for: identifiedModel)
        }
        return AudioOutput(value, model: identifiedModel)
    }

    /// `getStatusEx.project` — "WiiM_Ultra", "WiiM_AMP". Cached: it identifies
    /// the hardware and cannot change for the life of a plugin instance.
    ///
    /// Needed because output values are model-specific — 2 is Line Out on an
    /// Ultra and the speaker terminals on an Amp — so a value without a model
    /// can't be labelled honestly.
    func deviceModel() async -> String? {
        if let cachedModel { return cachedModel }
        guard let data = try? await send("getStatusEx"),
              let raw = try? JSONDecoder().decode(RawStatusEx.self, from: data),
              let project = raw.project else { return nil }
        cachedModel = project
        return project
    }

    /// Outputs to offer for this model, from the built-in table where we have
    /// one and the full range otherwise.
    ///
    /// Static, because **no device command enumerates outputs** — that was
    /// established by capture, not assumed: `getSoundCardOutputMode` is
    /// `unknown command`, and the name only appears in the vendor app's own
    /// telemetry, where it's an internal function the app translates to an
    /// integer before sending. Use `discoverOutputs()` to get the real set from
    /// hardware.
    func availableOutputs() async -> [AudioOutput] {
        AudioOutput.known(for: await deviceModel())
    }

    /// Asks the hardware which outputs it actually has, by trying each and
    /// keeping the ones that stick.
    ///
    /// This is the only way to learn a model's real output set: the device will
    /// answer `OK` to any value and silently keep its previous one, so nothing
    /// short of a readback distinguishes "switched" from "refused".
    ///
    /// **Disruptive on purpose-built hardware — audio moves, and goes silent on
    /// a jack with nothing plugged in.** Must be user-initiated, never run on a
    /// timer or at launch. The original output is restored even if a step
    /// throws, so an interrupted run doesn't leave audio somewhere unexpected.
    ///
    /// Returns values only. Naming them still needs a human: the device offers
    /// no labels, and which jack a value corresponds to can only be established
    /// by listening or by reading the vendor app.
    func discoverOutputs(range: ClosedRange<Int> = 0...7) async throws -> [AudioOutput] {
        let model = await deviceModel()
        guard let original = try await audioOutput() else {
            throw LinkplayError.badResponse
        }
        var accepted: [AudioOutput] = []
        do {
            for value in range {
                _ = try await send("setAudioOutputHardwareMode:\(value)")
                if try await audioOutput()?.rawValue == value {
                    accepted.append(AudioOutput(value, model: model))
                }
            }
        } catch {
            try? await restoreOutput(original)
            throw error
        }
        try await restoreOutput(original)
        // Remembered so the picker stops offering values this hardware refuses.
        // Keyed by model, since two Ultras have the same jacks.
        if let model {
            AudioOutput.recordDiscovered(accepted.map(\.rawValue), for: model)
        }
        return accepted
    }

    private func restoreOutput(_ output: AudioOutput) async throws {
        _ = try await send("setAudioOutputHardwareMode:\(output.rawValue)")
    }

    /// Switches output, **verifying by readback**.
    ///
    /// The device answers `OK` to values it then refuses — 0 and 5–7 on an Ultra
    /// all returned `OK` while leaving the output unchanged. Since which outputs
    /// exist varies by model (and Bluetooth/DLNA out appear to need pairing
    /// first), the honest approach is to attempt and confirm rather than to
    /// predict.
    func setAudioOutput(_ output: AudioOutput) async throws {
        _ = try await send("setAudioOutputHardwareMode:\(output.rawValue)")
        // Retried, not read once. A refusal here is *written down* and removes
        // the value from the picker for good, so concluding it from a single
        // readback that raced the device is the most expensive mistake this
        // function can make. See `confirm`.
        let landed = await confirm {
            try await self.audioOutput()?.rawValue == output.rawValue
        }
        // Every pick is a free experiment: the readback happens anyway, so
        // recording the outcome teaches the picker which values this hardware
        // actually has, without ever running a disruptive sweep.
        if let model = await deviceModel() {
            AudioOutput.record(output.rawValue, accepted: landed, for: model)
        }
        guard landed else { throw LinkplayError.badResponse }
    }

    // MARK: - Transport

    private func send(_ command: String) async throws -> Data {
        #if LARC_DEV
        // Fault injection, dev builds only. Partial read failures are exactly
        // the thing that can't be reproduced on demand — the bug they cause is
        // a control that silently draws blank — so this makes them switchable:
        //
        //   open build/Larc.app --args --fail-reads 0.5
        //
        // Fractional, so the *partial* case is reachable: at 0.5 a settings load
        // typically loses one or two of its four reads and keeps the rest.
        if let rate = LarcFaultInjection.readFailureRate, Double.random(in: 0..<1) < rate {
            throw URLError(.networkConnectionLost)
        }
        #endif
        if let known = scheme {
            do {
                return try await request(scheme: known, command: command)
            } catch {
                // Forget the cached scheme so the next call re-probes.
                scheme = nil
                throw error
            }
        }
        do {
            let data = try await request(scheme: "https", command: command)
            scheme = "https"
            return data
        } catch {
            let data = try await request(scheme: "http", command: command)
            scheme = "http"
            return data
        }
    }

    /// Characters left literal in the `command` query value.
    ///
    /// Matches how the WiiM app encodes: braces and quotes percent-encoded,
    /// `:` `,` `/` sent bare. Ordinary commands (`setPlayerCmd:vol:40`) are
    /// unaffected, but the room-correction commands take a JSON argument in the
    /// query string, and reproducing the app's exact bytes removes a variable —
    /// this firmware parses naively enough to be worth not testing.
    private static let commandAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: ":,/-._~")
        return set
    }()

    private func request(scheme: String, command: String) async throws -> Data {
        var components = URLComponents()
        components.scheme = scheme
        components.host = device.host
        components.path = "/httpapi.asp"
        guard let encoded = command.addingPercentEncoding(
            withAllowedCharacters: Self.commandAllowed
        ) else { throw LinkplayError.badURL }
        components.percentEncodedQuery = "command=\(encoded)"
        guard let url = components.url else { throw LinkplayError.badURL }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LinkplayError.badResponse
        }
        return data
    }

    // MARK: - Parsing

    private struct RawPlayerStatus: Decodable {
        var status: String?
        var vol: String?
        var mute: String?
        /// Position and length, both in milliseconds, both as strings like
        /// everything else this API returns.
        var curpos: String?
        var totlen: String?
        /// Numeric input identifier — see `AudioInput.mode`.
        var mode: String?
        var Title: String?
        var Artist: String?
        var Album: String?
    }

    /// `getMetaInfo` wraps everything in a `metaData` object. Every field is
    /// optional: which ones a source populates varies a lot (radio streams
    /// reliably carry station art, on-demand tracks are less consistent).
    private struct RawMetaInfo: Decodable {
        var metaData: RawMetaData?
    }

    struct RawMetaData: Decodable {
        var title: String?
        var artist: String?
        var album: String?
        var subtitle: String?
        var albumArtURI: String?
    }

    /// Linkplay hex-encodes Title/Artist/Album as UTF-8 bytes. Decode when the
    /// value is plausible hex; otherwise pass the raw string through (guards
    /// against titles like "2002" that happen to be valid hex but decode to
    /// control characters).
    static func decodeMetadataField(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        var result = value
        if value.count % 2 == 0, value.allSatisfy({ $0.isHexDigit }) {
            var bytes: [UInt8] = []
            bytes.reserveCapacity(value.count / 2)
            var index = value.startIndex
            while index < value.endIndex {
                let next = value.index(index, offsetBy: 2)
                guard let byte = UInt8(value[index..<next], radix: 16) else {
                    bytes.removeAll()
                    break
                }
                bytes.append(byte)
                index = next
            }
            if !bytes.isEmpty {
                let decoded = String(decoding: bytes, as: UTF8.self)
                let isClean = !decoded.contains("\u{FFFD}") && !decoded.unicodeScalars.contains {
                    $0.value < 0x20 && $0 != "\n" && $0 != "\t"
                }
                if isClean { result = decoded }
            }
        }
        return cleaned(unescapedEntities(result))
    }

    /// Undoes the XML entities the device leaves in metadata.
    ///
    /// Found in a real title: `we&apos;ll meet someday` displayed literally,
    /// apostrophe and all. The device's metadata comes out of DIDL-Lite XML and
    /// it doesn't finish unescaping before handing it over — so a title with an
    /// apostrophe, an ampersand or a quote arrives with the entity intact.
    ///
    /// A fixed table rather than an XML parser: this is a handful of known
    /// entities in a short string, and running a parser over a track title to
    /// recover one apostrophe would be the more fragile choice. `&amp;` is
    /// replaced **last**, so `&amp;apos;` — an ampersand that was itself escaped
    /// — doesn't turn into an apostrophe.
    private static func unescapedEntities(_ value: String) -> String {
        var result = value
        for (entity, character) in [
            ("&apos;", "'"), ("&#39;", "'"),
            ("&quot;", "\""), ("&#34;", "\""),
            ("&lt;", "<"), ("&gt;", ">"),
            ("&amp;", "&"),
        ] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }

    /// Placeholder strings devices send instead of leaving a field empty.
    ///
    /// Matched **exactly**, never by prefix: "Unknown Pleasures" is a real
    /// album, and a `hasPrefix("unknow")` test would silently eat it. Note
    /// "unknow" — WiiM's own misspelling, seen on BBC Asian Network, which is
    /// what this list was extended for.
    private static let placeholders: Set<String> = [
        "unknow", "unknown", "un_known", "unknow artist", "unknown artist",
        "unknow album", "unknown album", "none", "null", "-",
    ]

    /// Trims, then drops anything that's really "no value". Shared by both
    /// metadata paths — `getPlayerStatus`'s hex fields and `getMetaInfo`'s
    /// plain ones — so a placeholder can't sneak in through whichever one
    /// happens to be populated.
    static func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !placeholders.contains(trimmed.lowercased()) else { return nil }
        return trimmed
    }
}

// MARK: - Room correction (RoomFit)

/// Room correction on WiiM hardware, reverse-engineered — the vendor publishes
/// none of it. Four facts drive everything below, each of which cost real effort
/// to establish and none of which is guessable:
///
/// 1. **State is per input source.** Eight independent slots. `source_name` is
///    mandatory on every call; omit it and the device writes a `"default"` slot
///    the vendor's app never reads, which looks exactly like "nothing happened"
///    while the filter audibly changes.
/// 2. **The vendor's app writes all eight slots**, so its single selection is
///    global. Writing one slot leaves its UI showing whatever the others say.
/// 3. **Applying a filter and naming it are two different commands.**
///    `EQv2Load` installs the coefficients; `EQSetLV2SourceBand` records which
///    profile that was. `EQv2Load` alone leaves the name blank for an L/R
///    profile — the original bug this whole investigation started from.
/// 4. **The naming call must not carry band data.** With bands the request line
///    exceeds the device's limit and it answers HTTP 431; without them it is
///    ~150 bytes and succeeds. `EQv2Load` already supplied the coefficients.
///
/// Note the asymmetry in 3: the *reader* is `EQGetLV2SourceBandEx` but the
/// writer drops the `Ex`. `EQSetLV2SourceBandEx` does not exist.
extension LinkplayPlugin: RoomCorrecting {

    /// The room-correction DSP stage. `EQLevel` selects which engine a command
    /// addresses: 1 is the 10-band graphic EQ (plugin `Eq10HP`), 2 is parametric
    /// room correction (`EqNp`). Different plugins, different band schemas.
    private static let rcPlugin = "http://moddevices.com/plugins/caps/EqNp"
    private static let rcLevel = 2

    func roomFitProfiles() async throws -> [RoomFitProfile] {
        let data = try await send(
            "EQv2GetNewList:" + Self.json([
                ("pluginURI", .string(Self.rcPlugin)), ("EQLevel", .int(Self.rcLevel)),
            ])
        )
        let list = try JSONDecoder().decode(RawProfileList.self, from: data)
        // `preset` has been empty on every device seen, but include it — a
        // factory profile would land there and should still be selectable.
        return ((list.custom ?? []) + (list.preset ?? [])).compactMap { raw in
            guard let name = raw.Name, !name.isEmpty else { return nil }
            return RoomFitProfile(
                name: name,
                channelMode: raw.channelMode ?? "Stereo",
                calibratedOutput: raw.rc_output
            )
        }
    }

    /// Which source the device is playing from right now.
    ///
    /// Uses `EQGetBand` — the *level 1* graphic-EQ reader — because it takes no
    /// argument and volunteers `source_name` for the active source. The level-2
    /// reader can't do this: it requires the source as input, so it can only
    /// confirm what you already assumed. This is what makes it possible to read
    /// or write one slot instead of iterating all eight.
    /// Matched case-insensitively: the Amp reports `"HDMI"` where the Ultra
    /// reports `"wifi"`, while both accept lowercase as an argument.
    func activeSource() async throws -> AudioSource? {
        let data = try await send("EQGetBand")
        let raw = try? JSONDecoder().decode(RawEQState.self, from: data)
        return raw?.source_name.flatMap(AudioSource.init(deviceValue:))
    }

    /// What correction is actually in effect, in one call.
    ///
    /// Reads `.default` rather than the reported active source: experiment shows
    /// `default` is what drives both the audio and the vendor app's display,
    /// while the per-source slots either mirror it or (in `wifi`'s case) do
    /// nothing at all.
    func currentRoomFit() async throws -> RoomFitState {
        try await roomFitState(source: .default)
    }

    func roomFitState(source: AudioSource) async throws -> RoomFitState {
        let raw = try await readState(source: source)
        return RoomFitState(
            profileName: raw.Name ?? "",
            enabled: raw.EQStat == "On",
            channelMode: raw.channelMode ?? "Stereo"
        )
    }

    /// Selects a profile. **One call, one slot.**
    ///
    /// Established by controlled experiment (`tools/roomfit-experiment.py`),
    /// after an earlier version wrote sixteen calls across eight slots:
    ///
    /// - **`EQv2Load` is not needed.** The device already stores each profile's
    ///   coefficients; the load only re-installs them. Naming the profile is
    ///   what selects it, and the audio changes immediately either way.
    /// - **Only the `default` slot matters.** Writing it propagates to line-in,
    ///   optical, bluetooth, co-axial, hdmi and phono on its own.
    /// - **The `wifi` slot is inert.** Setting it alone changed neither the
    ///   sound nor the vendor app's display, even with audio playing over the
    ///   network — so despite `EQGetBand` reporting `wifi` as the active source,
    ///   that slot does not drive playback. Do not "optimise" by writing it.
    ///
    /// `channelMode` has to match the profile ("Stereo" vs "L/R") — hence taking
    /// the profile rather than a bare name, which also avoids a lookup call.
    /// Selecting a profile always enables correction — not by asking, but
    /// because *any* `EQSetLV2SourceBand` write switches it on. Confirmed the
    /// awkward way: with correction toggled off in the vendor's app, a write
    /// intended to keep it off turned it on.
    ///
    /// "None" disables via `EQSourceOff`, and the device keeps the profile name,
    /// so turning it back on restores the same profile.
    func setRoomFit(_ selection: RoomFitSelection) async throws {
        switch selection {
        case .profile(let profile):
            try await setPointer(
                name: profile.name,
                channelMode: profile.channelMode,
                enabled: true,
                source: .default
            )
        case .off:
            // `EQSourceOff` is the *only* way to disable correction. `EQStat`
            // in the setter's payload is ignored entirely — writing
            // `EQSetLV2SourceBand` with EQStat "Off" (or "off"/"0"/"false"/…)
            // returns OK and switches correction **on**, which is why selecting
            // a profile needs no separate enable step. `EQOn`/`EQOff` don't
            // reach this DSP stage either.
            //
            // The device keeps the profile name across this, so turning
            // correction back on restores the same profile with no caching here.
            _ = try await send(
                "EQSourceOff:" + Self.json([
                    ("pluginURI", .string(Self.rcPlugin)),
                    ("EQLevel", .int(Self.rcLevel)),
                    ("source_name", .string(AudioSource.default.rawValue)),
                ])
            )
        }
    }

    /// The profiles list and what's currently selected, for populating a picker.
    /// Two calls, run concurrently.
    func roomFitOptions() async throws -> (
        options: [RoomFitSelection], current: RoomFitSelection
    ) {
        async let profileList = roomFitProfiles()
        async let state = roomFitState(source: .default)
        let profiles = try await profileList
        // "None" first: it's the neutral choice, and putting it at the top means
        // its position doesn't move when profiles are added or removed.
        let options = [RoomFitSelection.off] + profiles.map(RoomFitSelection.profile)
        return (options, try await state.selection(among: profiles))
    }

    // MARK: Private

    private func readState(source: AudioSource) async throws -> RawEQState {
        let data = try await send(
            "EQGetLV2SourceBandEx:" + Self.json([
                ("pluginURI", .string(Self.rcPlugin)),
                ("EQLevel", .int(Self.rcLevel)),
                ("source_name", .string(source.rawValue)),
            ])
        )
        return try JSONDecoder().decode(RawEQState.self, from: data)
    }

    /// Records which profile a source is using. **Deliberately sends no band
    /// data** — see fact 4 above; including it returns HTTP 431.
    ///
    /// (`EQv2Load` used to run before this and is gone: the experiment showed
    /// the device already holds each profile's coefficients, so loading them
    /// again changed nothing an experimenter could detect.)
    private func setPointer(
        name: String, channelMode: String, enabled: Bool, source: AudioSource
    ) async throws {
        let data = try await send(
            "EQSetLV2SourceBand:" + Self.json([
                ("pluginURI", .string(Self.rcPlugin)),
                ("EQLevel", .int(Self.rcLevel)),
                ("source_name", .string(source.rawValue)),
                ("EQStat", .string(enabled ? "On" : "Off")),
                ("Name", .string(name)),
                ("channelMode", .string(channelMode)),
            ])
        )
        let result = try? JSONDecoder().decode(RawEQState.self, from: data)
        guard result?.status == "OK" else { throw LinkplayError.badResponse }
    }

    // MARK: JSON

    fileprivate enum JSONValue {
        case string(String)
        case int(Int)
    }

    /// Builds a compact JSON object preserving argument order.
    ///
    /// Hand-rolled rather than `JSONSerialization` because that emits keys in an
    /// arbitrary order, and this payload goes into a URL that has already proven
    /// length-sensitive — a stable, minimal encoding is worth more here than the
    /// generality. Escaping still follows JSON rules, since profile names are
    /// user-chosen and can contain anything.
    fileprivate static func json(_ pairs: [(String, JSONValue)]) -> String {
        let body = pairs.map { key, value -> String in
            switch value {
            case .string(let text): return "\(quoted(key)):\(quoted(text))"
            case .int(let number): return "\(quoted(key)):\(number)"
            }
        }.joined(separator: ",")
        return "{\(body)}"
    }

    private static func quoted(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

/// `getNewAudioOutputHardwareMode` — `source` and `audiocast` are also returned
/// and not yet understood; `audiocast` may relate to the app's Bluetooth/DLNA
/// outputs, which show as "Not Paired".
private struct RawStatusEx: Decodable {
    var project: String?
    var firmware: String?
    /// Reported as a string, like most numbers in this API.
    var max_volume: String?
}

private struct RawOutputMode: Decodable {
    var hardware: String?
    var source: String?
    var audiocast: String?
}

private struct RawProfileList: Decodable {
    var custom: [RawProfile]?
    var preset: [RawProfile]?
}

private struct RawProfile: Decodable {
    var Name: String?
    var channelMode: String?
    var rc_output: String?
}

/// Shared response shape for every EQ command — `EQGetBand`, `EQv2Load`,
/// `EQGetLV2SourceBandEx` and `EQSetLV2SourceBand` all answer with some subset
/// of these, so one type decodes them all. Band arrays are deliberately not
/// decoded: larc never needs the coefficients, only which profile is active.
private struct RawEQState: Decodable {
    var status: String?
    var Name: String?
    var EQStat: String?
    var channelMode: String?
    var source_name: String?
}

/// Accepts the self-signed TLS certificate presented by one specific device
/// host. Every other host gets default certificate validation.
private final class SelfSignedTrustDelegate: NSObject, URLSessionDelegate {
    private let host: String

    init(host: String) {
        self.host = host
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == host,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
