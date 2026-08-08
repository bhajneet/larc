import AppKit
import SwiftUI

/// A few colours sampled from album art, for use as a background tint.
///
/// Rendering the artwork *itself* as the tint was tried first and rejected
/// across several settings: a busy cover reads as noise behind text, and its
/// luminance is whatever the cover happens to be, so contrast could not be
/// controlled — a dark cover crushed the secondary subtitle, a pale one
/// vanished. Sampling a handful of dominant colours keeps the album's mood
/// while making luminance *ours* to set. That's the same reason Apple Music's
/// now-playing backgrounds never look noisy.
///
/// Samples are stored raw and flattened on demand by `colors(for:)`, so light
/// and dark mode get different saturation caps and brightness bands from one
/// download — and switching appearance re-tints without re-fetching anything.
struct ArtworkPalette: Equatable {
    /// Hue/saturation/brightness rather than NSColor, so the type is trivially
    /// Equatable (which `.animation(value:)` needs) and carries no colour-space
    /// baggage.
    struct Sample: Equatable {
        var hue: CGFloat
        var saturation: CGFloat
        var brightness: CGFloat

        /// The same transform `.contrast` and `.brightness` apply to the image,
        /// on this sample's brightness.
        ///
        /// Contrast first and pivoting on mid-grey, matching the modifier order
        /// on the watermark — the other way round, exposure would move the point
        /// contrast pivots about and the two layers would diverge.
        ///
        /// Only brightness is adjusted. SwiftUI's `.contrast` scales each RGB
        /// channel, which also pushes saturation; carrying that through here
        /// would mean reimplementing the filter rather than matching it, and the
        /// tint is a wash whose hue is the part that has to be right.
        func toned(by tone: Tone) -> Sample {
            var copy = self
            let pivoted = (brightness - 0.5) * CGFloat(tone.contrast) + 0.5
            copy.brightness = min(max(pivoted + CGFloat(tone.brightness), 0), 1)
            return copy
        }
    }

    private let samples: [Sample]

    /// **Every sampled cell, in place** — `gridSide` per row, top-left first,
    /// `nil` where the cell was too transparent to count.
    ///
    /// Kept, rather than thrown away after `luminance` and `contrast` are
    /// computed, because the tuning window draws it: the grid is what the app
    /// actually measures, and seeing it beside the cover is the difference
    /// between believing a number and understanding it. Positions are preserved
    /// — a compacted array would have made the picture a lie.
    let cells: [Sample?]
    let gridSide: Int

    /// Indices into `cells` of the ones that became gradient stops.
    let chosen: Set<Int>

    /// How bright the cover is overall, 0 (black) to 1 (white).
    ///
    /// Averaged over **every** sampled cell, not just the ones that survived the
    /// saturation floor — the question this answers is "how dark is this
    /// picture", and the near-black background of a dark cover is most of the
    /// answer. Taking it from the chosen samples would report the accent's
    /// brightness and call a black cover bright.
    let luminance: CGFloat

    /// How much the cover's brightness varies, 0 (flat) to 1 (black against
    /// white).
    ///
    /// **The 90th percentile minus the 10th, not max minus min.** A single
    /// bright cell — a logo, a specular highlight, one white letter — would
    /// otherwise report a flat cover as maximally busy. Percentiles ask how much
    /// of the picture differs rather than whether any of it does.
    let contrast: CGFloat



    /// Gradient stops for the given appearance.
    ///
    /// The clamping is the whole point of this approach: whatever the cover
    /// looks like, the tint lands in a predictable range, so it can never be so
    /// dark that secondary text stops being readable nor so saturated that it
    /// competes with the controls.
    @MainActor
    func colors(for scheme: ColorScheme) -> [Color] {
        resolvedStops(for: scheme).map(Self.color)
    }

    /// The gradient stops as HSB, after every adjustment.
    ///
    /// **Separate from `colors(for:)` so the result can be inspected.** A stop
    /// that comes out of this pipeline unchanged looks identical to one that was
    /// never adjusted, and the two have completely different fixes — the tuning
    /// window prints these so "is vibrance broken" is a question the screen
    /// answers. Exposure and contrast can pin a stop's brightness to 0 or 1,
    /// where saturation is either meaningless or held at the ceiling, and then
    /// no amount of vibrance moves anything.
    @MainActor
    func resolvedStops(for scheme: ColorScheme) -> [Sample] {
        // **Toned first, so the tint matches the watermark.** The watermark is
        // re-exposed at render time — a near-black cover is lifted to grey on a
        // light popover — and sampling the raw image meant the gradient stayed
        // the colour of a picture nobody was looking at. Same adjustment, same
        // numbers, applied here to the samples instead of to pixels.
        let tone = Self.tone(for: scheme, corner: corner)
        let ceiling = scheme == .dark
            ? ArtworkTuning.shared.saturationOnDark
            : ArtworkTuning.shared.saturationOnLight
        let vibrance = scheme == .dark
            ? ArtworkTuning.shared.vibranceOnDark
            : ArtworkTuning.shared.vibranceOnLight
        let toned = samples.map { $0.toned(by: tone) }
        var stops = toned.map { resolve($0, ceiling: ceiling, vibrance: vibrance) }

        // A single usable colour still needs two stops to be a gradient, so
        // pair it with a shifted copy of itself. Shift away from the band's
        // nearer limit so the second stop stays inside it.
        if stops.count == 1, let only = toned.first {
            let shift: CGFloat = scheme == .dark ? 0.12 : -0.12
            stops.append(resolve(only, ceiling: ceiling, vibrance: vibrance,
                                 shiftedBy: shift))
        }
        return stops
    }

    /// Exposure and contrast for the artwork, by appearance and by how dark the
    /// cover is.
    ///
    /// **Defined here rather than in the view** because two things need it and
    /// they must agree: the watermark applies it as `.brightness`/`.contrast`
    /// modifiers, and `colors(for:)` applies the same maths to its samples so
    /// the tint is drawn from the picture as displayed.
    ///
    /// Note the two scales differ — brightness is additive so **0** is
    /// untouched, contrast is multiplicative so **1** is.
    struct Tone {
        let brightness: Double
        let contrast: Double
    }

    @MainActor
    static func tone(for scheme: ColorScheme, corner: Corner) -> Tone {
        let tuning = ArtworkTuning.shared
        let exposure = scheme == .dark ? tuning.exposureOnDark : tuning.exposureOnLight
        let punch = scheme == .dark ? tuning.punchOnDark : tuning.punchOnLight
        return Tone(
            brightness: exposure.value(for: corner),
            contrast: punch.value(for: corner)
        )
    }

    /// A value per corner of the (brightness × contrast) square, interpolated
    /// bilinearly. Names describe the **cover**: `darkFlat` is a dark cover with
    /// little variation in it.
    /// A value per category, looked up rather than blended.
    ///
    /// **One category applies, never a mix.** This interpolated across the
    /// corners once, which meant every slider nudged every cover a little and
    /// none of them moved one cover cleanly — impossible to judge, because you
    /// could never see what a single number did on its own.
    ///
    /// The cost is a step at each threshold: two covers either side get visibly
    /// different treatment. That's the trade for a readable knob, and the
    /// thresholds are themselves adjustable.
    struct ToneMap: Equatable {
        var values: [Corner: Double]

        subscript(corner: Corner) -> Double {
            get { values[corner] ?? 0 }
            set { values[corner] = newValue }
        }

        func value(for corner: Corner) -> Double { self[corner] }
    }

    /// How dark the cover is, in three bands.
    enum Tone3: String, CaseIterable { case dark, mid, light }
    /// How much it varies, in three bands.
    enum Busy3: String, CaseIterable { case flat, mid, busy }

    /// One of the nine kinds of cover.
    ///
    /// Three bands per axis rather than two: "dark or light" put most real
    /// covers awkwardly near a threshold, where a small change in the artwork
    /// flipped the treatment. A middle band gives the common case its own
    /// values instead of forcing it to one extreme.
    struct Corner: Hashable, CaseIterable {
        var tone: Tone3
        var busy: Busy3

        static var allCases: [Corner] {
            Tone3.allCases.flatMap { tone in
                Busy3.allCases.map { Corner(tone: tone, busy: $0) }
            }
        }

        var label: String { "\(tone.rawValue) + \(busy.rawValue)" }
        var key: String { "\(tone.rawValue)_\(busy.rawValue)" }
    }

    /// Where this cover falls, against the tuning window's two thresholds.
    @MainActor
    var corner: Corner {
        let tuning = ArtworkTuning.shared
        let tone: Tone3 =
            luminance < tuning.darkMidSplit ? .dark
            : luminance < tuning.midLightSplit ? .mid : .light
        let busy: Busy3 =
            contrast < tuning.flatMidSplit ? .flat
            : contrast < tuning.midBusySplit ? .mid : .busy
        return Corner(tone: tone, busy: busy)
    }

    /// Exposure and contrast values live in `ArtworkTuning`, so they can be
    /// moved with sliders while the app runs. See that file for what each
    /// corner means; the defaults there are what these constants were.

    /// Brightness is left alone; saturation is capped **per stop**, by how
    /// bright that stop is.
    ///
    /// Not the old band, which capped every stop by the same number and clamped
    /// brightness too. The problem this solves is narrower: a bright, saturated
    /// stop — the red hand on OFF's *Dopamine* — turns the whole popover into a
    /// strong pink, while an equally saturated *dark* stop is just a deep colour
    /// and reads fine. So the ceiling follows the stop's own brightness, and a
    /// dark stop keeps all of its saturation.
    private func resolve(
        _ sample: Sample,
        ceiling: SaturationCeiling,
        vibrance: Vibrance,
        shiftedBy shift: CGFloat = 0
    ) -> Sample {
        let brightness = min(max(sample.brightness + shift, 0), 1)
        let lifted = vibrance.applied(to: sample.saturation, brightness: brightness)
        return Sample(
            hue: sample.hue,
            saturation: min(lifted, ceiling.at(brightness: brightness)),
            brightness: brightness
        )
    }

    static func color(_ sample: Sample) -> Color {
        Color(NSColor(
            hue: sample.hue,
            saturation: sample.saturation,
            brightness: sample.brightness,
            alpha: 1
        ))
    }

    /// A saturation *boost*, proportional to the headroom each stop has left.
    ///
    /// **Saturation cannot exceed 1, and this is not a way around that.** In HSB
    /// saturation is `(max − min) / max` of the three channels: at 1 the darkest
    /// channel is already 0 and the colour is on the edge of what sRGB can
    /// express for that hue and brightness. There is no 1.2.
    ///
    /// What there is room for is the *shape* of the boost. `s + k(1 − s)` moves a
    /// muted stop a long way and an already-vivid one barely at all, so it can
    /// be raised until the flat covers come alive without the vivid ones turning
    /// into poster paint — which is what a flat multiply does. That difference is
    /// the whole distinction between vibrance and saturation.
    ///
    /// Applied **before** the ceiling, which still has the last word: raising
    /// vibrance with a low `atBright` ceiling does nothing to bright stops, by
    /// design. The ceiling exists to stop a bright saturated stop washing the
    /// popover pink, and a boost that could overrule it would just reintroduce
    /// that.
    ///
    /// 0 at both ends leaves every stop exactly as sampled.
    struct Vibrance: Equatable {
        var atDark: CGFloat
        var atBright: CGFloat

        func applied(to saturation: CGFloat, brightness: CGFloat) -> CGFloat {
            let t = min(max(brightness, 0), 1)
            let amount = atDark + (atBright - atDark) * t
            return min(saturation + amount * (1 - saturation), 1)
        }
    }

    /// The most saturation a stop may keep, at its darkest and its brightest.
    /// Interpolated by the stop's brightness, so there's no threshold to sit on.
    struct SaturationCeiling: Equatable {
        var atDark: CGFloat
        var atBright: CGFloat

        func at(brightness: CGFloat) -> CGFloat {
            let t = min(max(brightness, 0), 1)
            return atDark + (atBright - atDark) * t
        }
    }

    /// Ceilings live in `ArtworkTuning` for the same reason.

    // MARK: - Sampling

    /// Builds a palette from an already-decoded image. Returns nil when there's
    /// nothing usable to sample — fully transparent art, or a bitmap context
    /// that couldn't be created.
    init?(cgImage: CGImage, grid: Int = 16) {
        let cells = Self.sample(cgImage, grid: grid)
        // Paired with their positions before anything filters them, so the
        // picks can be pointed at in the grid afterwards.
        let present = cells.enumerated().compactMap { index, cell in
            cell.map { (index: index, sample: $0) }
        }
        guard !present.isEmpty else { return nil }
        let picked = Self.choose(from: present)
        guard !picked.isEmpty else { return nil }
        self.cells = cells
        self.gridSide = grid
        self.chosen = Set(picked.map(\.index))
        self.samples = picked.map(\.sample)
        let sampled = present.map(\.sample)
        self.luminance = sampled.reduce(0) { $0 + $1.brightness }
            / CGFloat(sampled.count)

        let brightnesses = sampled.map(\.brightness).sorted()
        let low = brightnesses[Int(CGFloat(brightnesses.count - 1) * 0.1)]
        let high = brightnesses[Int(CGFloat(brightnesses.count - 1) * 0.9)]
        self.contrast = high - low
    }

    /// Draws the art into a small bitmap and reads every cell.
    ///
    /// **16×16, not 4×4.** Each cell is an *average*, so the grid decides how
    /// much of the cover gets blended into one number. At 4×4 a sixteenth of the
    /// image collapses to a single colour, which is fatal for the common case of
    /// a dark cover with a small bright accent: the accent averages with the
    /// dark around it and arrives desaturated, so the palette reports grey for a
    /// cover anyone would call green. At 16×16 an accent occupying a few percent
    /// of the art still owns whole cells.
    ///
    /// Sampling *positions* rather than content was considered and rejected —
    /// fixed points miss an accent that isn't where they look, which on this
    /// same cover is exactly the middle.
    ///
    /// The downscale still does the averaging for free — this only changes how
    /// much of the image each average covers.
    ///
    /// Returns one entry per cell **including the skipped ones**, so an index is
    /// a position: row `i / grid` from the top, column `i % grid`.
    private static func sample(_ cgImage: CGImage, grid: Int = 16) -> [Sample?] {
        var pixels = [UInt8](repeating: 0, count: grid * grid * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: grid,
                height: grid,
                bitsPerComponent: 8,
                bytesPerRow: grid * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return [] }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: grid, height: grid))

        var result: [Sample?] = []
        for index in stride(from: 0, to: pixels.count, by: 4) {
            // Skip mostly-transparent cells: art with a cut-out background
            // would otherwise contribute black.
            guard CGFloat(pixels[index + 3]) / 255 > 0.5 else {
                result.append(nil)
                continue
            }
            let color = NSColor(
                srgbRed: CGFloat(pixels[index]) / 255,
                green: CGFloat(pixels[index + 1]) / 255,
                blue: CGFloat(pixels[index + 2]) / 255,
                alpha: 1
            )
            result.append(Sample(
                hue: color.hueComponent,
                saturation: color.saturationComponent,
                brightness: color.brightnessComponent
            ))
        }
        return result
    }

    /// Picks the most colourful cells, skipping ones too close in hue to
    /// something already chosen — otherwise a cover that's 80% one colour
    /// yields three stops of the same colour and no gradient at all.
    ///
    /// Note this only rejects similar *hue*, not similar brightness: a
    /// monochrome cover with light and dark regions still yields several picks
    /// that differ in brightness, and the band preserves that difference.
    private static func choose(
        from samples: [(index: Int, sample: Sample)], count: Int = 3
    ) -> [(index: Int, sample: Sample)] {
        // **Grey is discarded before anything is ranked.**
        //
        // A near-grey cell has an arbitrary hue, so hue-distinctness treats it as
        // distinct from every real colour and it takes a slot. On a cover that is
        // mostly dark with one bright accent — deadmau5's SATRN, black with a
        // green glow — that meant one muddy green and two greys, and the tint
        // came out grey. The accent is the whole point of sampling; the
        // background is what the popover already looks like.
        let colourful = samples.filter { $0.sample.saturation >= saturationFloor }
        let pool = colourful.isEmpty ? samples : colourful

        let ranked = pool.sorted {
            $0.sample.saturation * $0.sample.brightness
                > $1.sample.saturation * $1.sample.brightness
        }
        var picked: [(index: Int, sample: Sample)] = []
        for candidate in ranked {
            if picked.allSatisfy({ hueDistance($0.sample, candidate.sample) > 0.08 }) {
                picked.append(candidate)
            }
            if picked.count == count { break }
        }
        // Every cell was near-grey and near-identical: fall back to the most
        // colourful one rather than returning nothing.
        return picked.isEmpty ? Array(ranked.prefix(1)) : picked
    }

    /// Below this a cell is grey as far as this palette is concerned.
    ///
    /// Low, because the job is only to separate "has a hue" from "doesn't" — a
    /// desaturated teal is still a teal and should be allowed to tint. Raising
    /// it discards more of a muted cover and falls back to raw samples sooner.
    private static let saturationFloor: CGFloat = 0.12

    /// Shortest distance between two hues on the 0...1 wheel, so red at 0.99
    /// and red at 0.01 read as the same hue rather than opposite ones.
    private static func hueDistance(_ a: Sample, _ b: Sample) -> CGFloat {
        let raw = abs(a.hue - b.hue)
        return min(raw, 1 - raw)
    }
}

/// A loaded piece of album art: the image, and the palette sampled from it.
///
/// One type because they come from **one download**. The watermark used to use
/// `AsyncImage` while `ArtworkPalette` fetched the same URL separately — two
/// requests for one image, relying on URLSession's cache to quietly collapse
/// them. Decoding once and handing back both removes that.
struct Artwork: Equatable {
    let url: URL
    let image: Image
    let palette: ArtworkPalette

    /// Identity is the URL. That's exactly the right granularity for
    /// `.animation(value:)`: a different track means a different URL means
    /// re-animate, and `Image` isn't Equatable anyway.
    static func == (lhs: Artwork, rhs: Artwork) -> Bool {
        lhs.url == rhs.url
    }

    /// The larc logo, for when there is no cover to show.
    ///
    /// **A real `Artwork`, not a special case downstream.** HDMI, optical and
    /// most radio give no art at all, which left the popover flat while every
    /// other source got a tint — so the absence of a cover was the most visible
    /// state in the app. Building the logo into the same type means it goes
    /// through the same palette, the same categorisation and the same two
    /// layers, and nothing that draws artwork needs to know it is looking at a
    /// substitute.
    ///
    /// Its `url` is a scheme that resolves to nothing, which is the point:
    /// `Artwork`'s identity is its URL, so the logo compares equal to itself and
    /// unequal to every real cover, and the cross-fade between them works
    /// without any of this being a case anywhere.
    ///
    /// Nil when the resource is missing — the bundle carried nothing but a
    /// binary until this, so an old build or a `swift build` that skipped
    /// resources simply has no fallback rather than crashing over one.
    static let fallback: Artwork? = {
        guard let url = Bundle.main.url(forResource: "larc-logo", withExtension: "png"),
              let nsImage = NSImage(contentsOf: url),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let palette = ArtworkPalette(cgImage: cgImage)
        else { return nil }
        return Artwork(url: fallbackIdentity, image: Image(nsImage: nsImage), palette: palette)
    }()

    /// A scheme that resolves to nothing, so it can't collide with a real cover.
    static let fallbackIdentity = URL(string: "larc-fallback:logo")!

    /// True for the logo. Callers need this because the logo means something
    /// different from a cover: a cover is what's playing, the logo is what we
    /// show when nothing can be.
    var isFallback: Bool { url == Self.fallbackIdentity }

    /// Downloads, decodes, and samples. Returns nil for anything that fails —
    /// unreachable URL, undecodable data, unsamplable image — because artwork is
    /// decoration and its absence must cost nothing.
    ///
    /// Uses `localTrustSession`, which accepts self-signed certificates from
    /// private-IP hosts — see that property for why.
    static func load(from url: URL, session: URLSession = Artwork.localTrustSession) async -> Artwork? {
        guard let (data, _) = try? await session.data(from: httpsUpgraded(url)),
              let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let palette = ArtworkPalette(cgImage: cgImage)
        else { return nil }
        return Artwork(url: url, image: Image(nsImage: nsImage), palette: palette)
    }

    /// Rewrites `http` to `https` for public hosts.
    ///
    /// App Transport Security blocks plain-HTTP loads to public hosts outright:
    /// the connection is never attempted, so this is *not* a certificate problem
    /// and `localTrustSession`'s delegate never even runs. TuneIn is the case
    /// that forced this — it returns `http://cdn-profiles.tunein.com/…` for some
    /// stations and `https://` for others on the same CDN host, which is why
    /// artwork appeared for some stations and not others. Since that host
    /// demonstrably serves TLS, upgrading the scheme fixes it without weakening
    /// anything or naming a domain in Info.plist.
    ///
    /// Private hosts are deliberately left alone: their plain HTTP is already
    /// permitted by `NSAllowsLocalNetworking`, and forcing https on a device
    /// that only speaks plaintext would break art that currently works.
    private static func httpsUpgraded(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              let host = url.host,
              !PrivateNetworkTrustDelegate.isPrivateAddress(host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.scheme = "https"
        return components.url ?? url
    }

    /// Session for artwork loads. Accepts self-signed certificates, but **only
    /// from private-IP hosts**.
    ///
    /// Needed because real sources serve art from the LAN over HTTPS with an
    /// untrusted certificate. Plex is the case that forced this: `getMetaInfo`
    /// returns e.g.
    /// `https://<plex-host>:32400/photo/:/transcode?…&X-Plex-Token=…` — a bare
    /// LAN IP with a self-signed cert, which `URLSession.shared` rejects during
    /// the handshake, so both the tint and the watermark silently vanished.
    ///
    /// Note `NSAllowsLocalNetworking` does *not* cover this. It exempts App
    /// Transport Security's transport requirements (plain HTTP, older TLS) but
    /// not certificate **trust** evaluation, which is a separate gate.
    ///
    /// Nor does `LinkplayPlugin`'s `SelfSignedTrustDelegate`: it matches
    /// `protectionSpace.host` against the *device's* address, and artwork
    /// routinely lives on a different machine (the WiiM and the Plex server are
    /// two different LAN hosts). The scoping that makes that delegate safe is exactly
    /// what makes it useless here.
    ///
    /// **The security trade, stated plainly:** an attacker already on the LAN
    /// could MITM an artwork fetch and capture whatever credential is embedded
    /// in its URL, such as `X-Plex-Token`. That exposure already exists though —
    /// the token arrives *inside* the `getMetaInfo` response, fetched from the
    /// device over HTTPS with a self-signed cert we accept without verification.
    /// Anyone able to intercept the artwork request can read the token from the
    /// metadata request instead, so declining to send it onward protects
    /// nothing and only costs the artwork.
    static let localTrustSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 15
        return URLSession(
            configuration: config,
            delegate: PrivateNetworkTrustDelegate(),
            delegateQueue: nil
        )
    }()
}

/// Accepts server trust unconditionally, but only when the host is a private-IP
/// literal. Public hosts fall through to normal validation, so a compromised CDN
/// certificate is still rejected.
private final class PrivateNetworkTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              Self.isPrivateAddress(challenge.protectionSpace.host)
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    /// True only for bare private/loopback/link-local IPv4 literals.
    ///
    /// Hostnames are deliberately excluded, even ones that look local like
    /// `nas.local`: a name resolves to wherever DNS says, so "looks local" isn't
    /// verifiable, whereas an RFC1918 literal cannot be routed off the LAN. IPv6
    /// is excluded for the same reason plus lack of a case to test against.
    static func isPrivateAddress(_ host: String) -> Bool {
        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4, host.split(separator: ".").count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (10, _): return true            // 10.0.0.0/8
        case (127, _): return true           // loopback
        case (169, 254): return true         // link-local
        case (172, 16...31): return true     // 172.16.0.0/12
        case (192, 168): return true         // 192.168.0.0/16
        default: return false
        }
    }
}
