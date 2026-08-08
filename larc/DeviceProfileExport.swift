import Foundation

/// A shareable description of what a device model can do, for growing larc's
/// built-in capability tables from real hardware.
///
/// **Opt-in, user-initiated, and it never leaves the machine on its own.** larc
/// has no server and sends no telemetry; this produces text the maintainer can read
/// in full and then choose to paste into a GitHub issue. That is the whole
/// mechanism — a contribution, not a report.
///
/// Why it's worth having: capability values are per *model*, not per unit, so
/// one person's WiiM Amp answers for every WiiM Amp. Once someone confirms which
/// outputs their model accepts and what each is called, that mapping can ship in
/// the next release and nobody with that model has to work it out again.
///
/// **Privacy is by construction, not by filtering.** This builds a fixed set of
/// fields from typed values; there is no path by which a raw response, a URL, a
/// token, an IP address or a device serial can end up in it. That matters
/// concretely here: packet captures taken while investigating this API contained
/// the maintainer's Plex token, and a "just dump what we know" export would have
/// shipped it. Deliberately excluded: device uuid, MAC, host, network name, the
/// user-assigned device name, and anything from `getStatusEx` beyond model and
/// firmware.
struct DeviceProfileExport: Codable, Equatable {
    /// e.g. "WiiM_AMP" — the key the tables are built on.
    var model: String
    /// Included because capabilities change with firmware: outputs can appear,
    /// and a report against an old version shouldn't silently overwrite a newer
    /// one.
    var firmware: String?
    /// Values the device accepted, observed during normal use or a sweep.
    var acceptedOutputs: [Int]
    /// Values it silently refused. Just as useful — they're what a picker on
    /// this model should never offer.
    var refusedOutputs: [Int]
    /// What the maintainer says each output actually is: `["2": "Speakers"]`.
    /// The one part no device will ever tell us, and the reason a human has to
    /// be in this loop at all.
    var outputLabels: [String: String]
    /// Inputs that switched successfully, by their `switchmode` name.
    var workingInputs: [String]
    /// Channel-mode values the device accepted.
    var channelModes: [Int]
    var larcVersion: String

    /// Everything larc knows about this model, assembled from what it has
    /// already observed. `labels` comes from the user, since nothing else can
    /// supply it.
    static func build(
        identity: DeviceIdentity,
        labels: [Int: String],
        workingInputs: [AudioInput],
        channelModes: [ChannelMode],
        larcVersion: String = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "dev"
    ) -> DeviceProfileExport? {
        // No model, nothing to contribute: a report that can't be keyed to
        // hardware helps nobody and is just data about a person.
        guard let model = identity.model else { return nil }
        return DeviceProfileExport(
            model: model,
            firmware: identity.firmware,
            acceptedOutputs: AudioOutput.discovered(for: model) ?? [],
            refusedOutputs: AudioOutput.refused(for: model),
            outputLabels: Dictionary(
                uniqueKeysWithValues: labels.map { (String($0.key), $0.value) }
            ),
            workingInputs: workingInputs.map(\.rawValue),
            channelModes: channelModes.map(\.rawValue),
            larcVersion: larcVersion
        )
    }

    /// Pretty-printed with sorted keys so the maintainer can read exactly what
    /// they'd be sharing before they share it, and so two reports of the same
    /// device produce identical text rather than a spurious diff.
    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private var summary: String {
        "Adding capability data for \(model)"
            + (firmware.map { " (firmware \($0))" } ?? "")
    }

    /// A prefilled GitHub issue. Opening a URL is the entire transport — no
    /// account on our side, no server, and the maintainer sees the body before
    /// submitting. Requires *their* GitHub account, which is why `mailtoURL`
    /// exists alongside it.
    func issueURL(repository: String) -> URL? {
        var components = URLComponents(
            string: "https://github.com/\(repository)/issues/new"
        )
        components?.queryItems = [
            URLQueryItem(name: "title", value: "Device profile: \(model)"),
            URLQueryItem(name: "labels", value: "device-profile"),
            URLQueryItem(name: "body", value: """
                \(summary).

                ```json
                \(json)
                ```
                """),
        ]
        return components?.url
    }

    /// A prefilled email, for anyone without a GitHub account — which is most
    /// people who own a streamer.
    ///
    /// Built with `percentEncodedQuery` rather than `queryItems` because
    /// `URLComponents` leaves `+` unescaped in a query value, and mail clients
    /// decode it as a space; JSON containing one would arrive corrupted. The
    /// body is a few hundred bytes, well inside the ~2 KB that clients start
    /// truncating at.
    func mailtoURL(to address: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~")
        )
        guard let subject = "Device profile: \(model)"
                .addingPercentEncoding(withAllowedCharacters: allowed),
              let body = "\(summary).\n\n\(json)\n"
                .addingPercentEncoding(withAllowedCharacters: allowed)
        else { return nil }
        return URL(string: "mailto:\(address)?subject=\(subject)&body=\(body)")
    }

    /// The JSON alone, for the third route: copy to clipboard, or save to a
    /// file, and send it however they like. Needs no account and no mail client
    /// configured — worth having, since a Mac with neither is common enough and
    /// a dead-end "Share" button is worse than no button.
    var shareableText: String { "\(summary)\n\n\(json)" }
}
