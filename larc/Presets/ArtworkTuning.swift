import Combine
import SwiftUI

/// Live values for everything that decides how the artwork is drawn.
///
/// **Why this exists as an object rather than as constants.** Tuning these by
/// editing a file means a rebuild per guess, and several of them interact — the
/// tone map moves the brightness that the saturation ceiling keys off, and the
/// tint's opacity changes how much of either you can see. Judging that loop at
/// one guess per build is what produced a knob nobody could perceive the effect
/// of. Sliders collapse it to seconds.
///
/// **The numbers are not here.** Each knob is declared and explained here and
/// its value comes from `ArtworkDefaults`, which the tuning window rewrites —
/// one source of truth, and a tuning session that ends in a diff instead of in
/// a copy-paste. This file is the reasoning; that file is the state.
///
/// **Only render-time knobs live here.** The sampling constants — `grid`,
/// `saturationFloor`, `hueDistance` — stay in `ArtworkPalette`, because they run
/// during the download on a background task while these are read on the main
/// thread during rendering. Mixing the two would mean guarding this against data
/// races for the sake of a developer tool.
///
/// **In a release build this is only the values.** Everything that makes them
/// editable — persistence, the Current/Latest comparison, and writing back to
/// the source tree — is `LARC_DEV` only, along with the window itself. Two of
/// those have no meaning without it, and the third would bake the absolute path
/// of the machine that compiled the app into the binary.
@MainActor
final class ArtworkTuning: ObservableObject {
    static let shared = ArtworkTuning()

    #if LARC_DEV
    private var cancellables: Set<AnyCancellable> = []
    /// The values committed in `ArtworkDefaults.swift`, captured before
    /// anything is loaded — what "Current" shows and what "Discard" returns to.
    ///
    /// Implicitly-unwrapped so every `@Published` below is initialised from its
    /// own declaration before the initialiser body runs — which is what makes
    /// "capture the defaults" a single line rather than a second copy of all
    /// nineteen values.
    private var shipped: Snapshot!

    /// Which set of values the window is showing.
    ///
    /// **`current` is a look, not a state.** It swaps the committed values in so
    /// the two can be compared on the same cover, holds the edits aside, and
    /// puts them back on the way out. Nothing is saved while it's up — the
    /// debounced write would otherwise quietly replace a session's work with
    /// the values it was being compared against.
    enum Showing { case latest, current }
    @Published private(set) var showing: Showing = .latest
    private var stashed: Snapshot?

    /// Whether the live values differ from what is committed in
    /// `ArtworkDefaults.swift` — asked of the edits even while `current` is
    /// being shown, so switching to the comparison doesn't claim the session
    /// never happened.
    var hasChanges: Bool { (stashed ?? snapshot()) != shipped }

    func show(_ which: Showing) {
        guard which != showing else { return }
        switch which {
        case .current:
            stashed = snapshot()
            apply(shipped)
        case .latest:
            if let stashed { apply(stashed) }
            stashed = nil
        }
        showing = which
    }
    #endif

    private init() {
        #if LARC_DEV
        shipped = snapshot()
        // **The source file wins whenever it has moved.**
        //
        // Stored edits are applied over the compiled-in values, so without this
        // check, editing `ArtworkDefaults.swift` and rebuilding did nothing at
        // all on a machine that had ever opened this window — the blob quietly
        // reinstated the old numbers and the file looked broken. The baseline
        // records which committed values a session was built on; when it no
        // longer matches, the file changed underneath and the session it
        // belonged to is gone with it.
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode(Stored.self, from: data),
           stored.baseline == shipped {
            apply(stored.values)
        }
        // **Debounced, and after the change rather than before it.**
        // `objectWillChange` fires on `willSet`, so reading the values from it
        // directly would store the previous ones. A debounce both defers past
        // the write and collapses a slider drag's few hundred updates into one.
        objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] in self?.save() }
            .store(in: &cancellables)
        #endif
    }

    // MARK: Where the four categories divide

    /// Where the three luminance bands and the three contrast bands divide.
    ///
    /// Three bands, not two: with a single split, most real covers landed near
    /// it, and a small change in the artwork flipped the whole treatment. A
    /// middle band gives the common case its own values.
    /// The two sliders are the **edges of the middle band**: below the first is
    /// dark, above the second is light, between them is mid. Same for the
    /// contrast pair.
    ///
    /// Each setter pushes the other slider rather than letting them cross —
    /// dragging the lower edge above the upper one would otherwise invert the
    /// band and classify everything as mid, which looks like the categories
    /// have stopped working.
    @Published var darkMidSplit = ArtworkDefaults.darkMidSplit {
        didSet { if midLightSplit < darkMidSplit { midLightSplit = darkMidSplit } }
    }
    @Published var midLightSplit = ArtworkDefaults.midLightSplit {
        didSet { if darkMidSplit > midLightSplit { darkMidSplit = midLightSplit } }
    }
    @Published var flatMidSplit = ArtworkDefaults.flatMidSplit {
        didSet { if midBusySplit < flatMidSplit { midBusySplit = flatMidSplit } }
    }
    @Published var midBusySplit = ArtworkDefaults.midBusySplit {
        didSet { if flatMidSplit > midBusySplit { flatMidSplit = midBusySplit } }
    }

    // MARK: Tone — exposure and contrast, one value per category

    @Published var exposureOnLight = ArtworkDefaults.exposureOnLight
    @Published var exposureOnDark = ArtworkDefaults.exposureOnDark
    @Published var punchOnLight = ArtworkDefaults.punchOnLight
    @Published var punchOnDark = ArtworkDefaults.punchOnDark

    // MARK: Per-stop saturation ceiling

    @Published var saturationOnLight = ArtworkDefaults.saturationOnLight
    @Published var saturationOnDark = ArtworkDefaults.saturationOnDark

    // MARK: Per-stop saturation boost

    /// Defaults to nothing at both ends, so the tint is exactly what it was
    /// until someone moves these.
    @Published var vibranceOnLight = ArtworkDefaults.vibranceOnLight
    @Published var vibranceOnDark = ArtworkDefaults.vibranceOnDark

    // MARK: How strongly each layer is drawn

    @Published var tintOpacityOnLight = ArtworkDefaults.tintOpacityOnLight
    @Published var tintOpacityOnDark = ArtworkDefaults.tintOpacityOnDark
    /// **Per category, like the tint's.** It was one number per appearance
    /// while everything around it varied by what the cover is — which made it
    /// the one part of the equation that couldn't answer the question this
    /// window exists to ask. A busy cover needs less of itself behind the
    /// controls than a flat one at the same brightness, and there was no way to
    /// say so. Every category starts at the value the single number held.
    @Published var watermarkOpacityOnLight = ArtworkDefaults.watermarkOpacityOnLight
    @Published var watermarkOpacityOnDark = ArtworkDefaults.watermarkOpacityOnDark

    #if LARC_DEV
    // MARK: Writing the values back

    /// Where `ArtworkDefaults.swift` sits **on the machine this build was
    /// compiled on**.
    ///
    /// `#filePath` is baked in at compile time, so on the maintainer's Mac it points
    /// at the real file in the checkout and on anyone else's it points at a
    /// directory that isn't there — which `writeToSource` treats as "no source
    /// tree", not as an error. The tuning window is developer-only and slated
    /// for removal before shipping either way; see ROADMAP.md.
    static var sourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ArtworkDefaults.swift")
    }

    /// Rewrites `ArtworkDefaults.swift` with the values as they stand.
    ///
    /// **The whole file, not a patched region.** Rewriting part of a file means
    /// parsing it, and a generator that has to parse its own output is a
    /// generator that eventually corrupts it. This emits every value it owns
    /// and nothing else — which is exactly why the numbers were moved out of
    /// `ArtworkTuning` in the first place, so that nothing worth keeping lives
    /// in the file being overwritten.
    @discardableResult
    func writeToSource() -> String {
        let url = Self.sourceURL
        guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path)
        else { return "No source tree at \(url.deletingLastPathComponent().path)" }
        do {
            try generatedSource.write(to: url, atomically: true, encoding: .utf8)
            // **The file is now the committed set, so it becomes the baseline.**
            // `shipped` is read from the compiled-in `ArtworkDefaults`, which
            // this build still holds at the old values until it is rebuilt —
            // leaving Current showing the set that was just replaced and Latest
            // still offering to return to values now identical to it.
            shipped = snapshot()
            save()
            return "Wrote \(url.lastPathComponent) — Current is now these values"
        } catch {
            return "Couldn't write: \(error.localizedDescription)"
        }
    }

    /// The complete contents of `ArtworkDefaults.swift`.
    var generatedSource: String {
        func map(_ name: String, _ m: ArtworkPalette.ToneMap) -> String {
            let rows = ArtworkPalette.Corner.allCases.map {
                "        .init(tone: .\($0.tone.rawValue), busy: .\($0.busy.rawValue)): \(f(m[$0])),"
            }.joined(separator: "\n")
            return "    static let \(name) = ArtworkPalette.ToneMap(values: [\n\(rows)\n    ])"
        }
        func ceiling(_ name: String, _ c: ArtworkPalette.SaturationCeiling) -> String {
            "    static let \(name) = ArtworkPalette.SaturationCeiling"
                + "(atDark: \(f(c.atDark)), atBright: \(f(c.atBright)))"
        }
        func vibrance(_ name: String, _ v: ArtworkPalette.Vibrance) -> String {
            "    static let \(name) = ArtworkPalette.Vibrance"
                + "(atDark: \(f(v.atDark)), atBright: \(f(v.atBright)))"
        }
        return """
        import CoreGraphics

        /// **Generated by the Artwork tuning window — its "Write to source" button.**
        /// Edit it there and press the button; anything typed here by hand is lost the
        /// next time it writes.
        ///
        /// The numbers live apart from `ArtworkTuning` so there is exactly one source
        /// of truth for them. That file declares each knob and documents why it exists;
        /// this one is only what the knobs are currently set to, which is the part that
        /// changes in an afternoon and belongs in a diff.
        enum ArtworkDefaults {
            static let darkMidSplit: CGFloat = \(f(darkMidSplit))
            static let midLightSplit: CGFloat = \(f(midLightSplit))
            static let flatMidSplit: CGFloat = \(f(flatMidSplit))
            static let midBusySplit: CGFloat = \(f(midBusySplit))

        \(map("exposureOnLight", exposureOnLight))
        \(map("exposureOnDark", exposureOnDark))
        \(map("punchOnLight", punchOnLight))
        \(map("punchOnDark", punchOnDark))

        \(ceiling("saturationOnLight", saturationOnLight))
        \(ceiling("saturationOnDark", saturationOnDark))
        \(vibrance("vibranceOnLight", vibranceOnLight))
        \(vibrance("vibranceOnDark", vibranceOnDark))

        \(map("tintOpacityOnLight", tintOpacityOnLight))
        \(map("tintOpacityOnDark", tintOpacityOnDark))
        \(map("watermarkOpacityOnLight", watermarkOpacityOnLight))
        \(map("watermarkOpacityOnDark", watermarkOpacityOnDark))
        }

        """
    }

    private func f(_ value: some BinaryFloatingPoint) -> String {
        String(format: "%.2f", Double(value))
    }

    // MARK: Persistence

    /// Throw the session away and go back to what is committed.
    ///
    /// Worth a button because persistence has a sharp edge: once a value is
    /// stored, editing `ArtworkDefaults.swift` by hand stops having any effect
    /// on a machine that has ever opened this window. Without a way back, a
    /// session that went badly would be the permanent state of the app.
    func discardChanges() {
        stashed = nil
        showing = .latest
        apply(shipped)
    }

    private static let defaultsKey = "artworkTuning"

    /// What was persisted, and which committed values it was edited against.
    private struct Stored: Codable {
        var baseline: Snapshot
        var values: Snapshot
    }

    /// **Every field optional.** A stored blob outlives the shape of this type —
    /// `vibrance` was added after the first values were saved — and a strict
    /// decode would have thrown the whole afternoon away over one missing key.
    /// Anything absent keeps whatever the build ships.
    private struct Snapshot: Codable, Equatable {
        struct Pair: Codable, Equatable {
            var atDark: Double
            var atBright: Double
        }

        var darkMidSplit: Double?
        var midLightSplit: Double?
        var flatMidSplit: Double?
        var midBusySplit: Double?
        var exposureOnLight: [String: Double]?
        var exposureOnDark: [String: Double]?
        var punchOnLight: [String: Double]?
        var punchOnDark: [String: Double]?
        var saturationOnLight: Pair?
        var saturationOnDark: Pair?
        var vibranceOnLight: Pair?
        var vibranceOnDark: Pair?
        var tintOpacityOnLight: [String: Double]?
        var tintOpacityOnDark: [String: Double]?
        var watermarkOpacityOnLight: [String: Double]?
        var watermarkOpacityOnDark: [String: Double]?
    }

    /// Keyed by `Corner.key` rather than by the corner itself: a struct of two
    /// enums is not a `Codable` dictionary key, and a string that reads
    /// `dark_flat` in the plist is worth more than one that doesn't when the
    /// question is why a value came back wrong.
    private func snapshot() -> Snapshot {
        func keyed(_ map: ArtworkPalette.ToneMap) -> [String: Double] {
            Dictionary(uniqueKeysWithValues: map.values.map { corner, value in
                (corner.key, value)
            })
        }
        return Snapshot(
            darkMidSplit: Double(darkMidSplit),
            midLightSplit: Double(midLightSplit),
            flatMidSplit: Double(flatMidSplit),
            midBusySplit: Double(midBusySplit),
            exposureOnLight: keyed(exposureOnLight),
            exposureOnDark: keyed(exposureOnDark),
            punchOnLight: keyed(punchOnLight),
            punchOnDark: keyed(punchOnDark),
            saturationOnLight: .init(atDark: Double(saturationOnLight.atDark),
                                     atBright: Double(saturationOnLight.atBright)),
            saturationOnDark: .init(atDark: Double(saturationOnDark.atDark),
                                    atBright: Double(saturationOnDark.atBright)),
            vibranceOnLight: .init(atDark: Double(vibranceOnLight.atDark),
                                   atBright: Double(vibranceOnLight.atBright)),
            vibranceOnDark: .init(atDark: Double(vibranceOnDark.atDark),
                                  atBright: Double(vibranceOnDark.atBright)),
            tintOpacityOnLight: keyed(tintOpacityOnLight),
            tintOpacityOnDark: keyed(tintOpacityOnDark),
            watermarkOpacityOnLight: keyed(watermarkOpacityOnLight),
            watermarkOpacityOnDark: keyed(watermarkOpacityOnDark)
        )
    }

    private func apply(_ stored: Snapshot) {
        func map(_ keyed: [String: Double]?, into target: inout ArtworkPalette.ToneMap) {
            guard let keyed else { return }
            for corner in ArtworkPalette.Corner.allCases {
                if let value = keyed[corner.key] { target[corner] = value }
            }
        }
        // The splits are assigned low-then-high on each axis so their
        // push-the-other-one setters can't reorder a stored pair on the way in.
        if let value = stored.darkMidSplit { darkMidSplit = CGFloat(value) }
        if let value = stored.midLightSplit { midLightSplit = CGFloat(value) }
        if let value = stored.flatMidSplit { flatMidSplit = CGFloat(value) }
        if let value = stored.midBusySplit { midBusySplit = CGFloat(value) }
        map(stored.exposureOnLight, into: &exposureOnLight)
        map(stored.exposureOnDark, into: &exposureOnDark)
        map(stored.punchOnLight, into: &punchOnLight)
        map(stored.punchOnDark, into: &punchOnDark)
        if let pair = stored.saturationOnLight {
            saturationOnLight = .init(atDark: CGFloat(pair.atDark),
                                      atBright: CGFloat(pair.atBright))
        }
        if let pair = stored.saturationOnDark {
            saturationOnDark = .init(atDark: CGFloat(pair.atDark),
                                     atBright: CGFloat(pair.atBright))
        }
        if let pair = stored.vibranceOnLight {
            vibranceOnLight = .init(atDark: CGFloat(pair.atDark),
                                    atBright: CGFloat(pair.atBright))
        }
        if let pair = stored.vibranceOnDark {
            vibranceOnDark = .init(atDark: CGFloat(pair.atDark),
                                   atBright: CGFloat(pair.atBright))
        }
        map(stored.tintOpacityOnLight, into: &tintOpacityOnLight)
        map(stored.tintOpacityOnDark, into: &tintOpacityOnDark)
        map(stored.watermarkOpacityOnLight, into: &watermarkOpacityOnLight)
        map(stored.watermarkOpacityOnDark, into: &watermarkOpacityOnDark)
    }

    private func save() {
        // Never while comparing: what's live is the committed set, and storing
        // it would be storing the thing the session is being measured against.
        guard showing == .latest,
              let data = try? JSONEncoder().encode(
                  Stored(baseline: shipped, values: snapshot())
              ) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
    #endif
}
