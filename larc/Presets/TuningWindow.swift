#if LARC_DEV
import SwiftUI

/// A floating window for working on the artwork layers: what the cover is, what
/// each layer looks like alone, and every value that decides it.
///
/// **Compiled only with `-D LARC_DEV`** (`./build.sh --dev`). It shipped in
/// release builds for as long as the layers were being worked on, because
/// judging them wanted a prod build — but it writes to the source tree and
/// carries the absolute path of the machine it was built on, so it is the one
/// thing here that must never reach a user.
///
/// It floats, so it survives the popover closing on an outside click, and
/// `PopoverView` observes `ArtworkTuning`, so the popover redraws mid-drag.
enum TuningWindow {
    private static var window: NSWindow?

    @MainActor
    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            DeviceController.shared.tuningWindowOpen = true
            return
        }
        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 800),
            styleMask: [.titled, .closable, .resizable, .utilityWindow,
                        .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.title = "Artwork"
        created.level = .floating
        created.isReleasedWhenClosed = false
        // **Transparent to the desktop, like the popover's window is.**
        //
        // A material shows what is *behind* it. In an ordinary opaque window
        // there is nothing behind but the window's own fill, so
        // `.glassBackground` rendered as flat grey and the swatches looked
        // nothing like the popover — which is transparent and blurs whatever is
        // on screen. Clearing the window's own background is what lets the same
        // modifier do the same thing here.
        created.isOpaque = false
        created.backgroundColor = .clear
        created.titlebarAppearsTransparent = true
        created.contentViewController = NSHostingController(rootView: TuningView())
        // **After the content view controller, not before.** Assigning one
        // resizes the window to that controller's fitting size, so the
        // `contentRect` above is discarded — which is why the window came up
        // short and had to be dragged taller every launch.
        // Twice the old width, which is also what doubles the previews: the
        // swatches take their side from the strip's measured width, so at 960
        // each one lands at about 220 — close enough to the popover's own 240
        // that the mock pill and now-playing sit at nearly the size they will
        // really be, rather than being judged in miniature.
        created.setContentSize(NSSize(width: 960, height: 800))
        created.center()
        created.makeKeyAndOrderFront(nil)
        // Tells the controller to poll fast while this is up, and to stop when
        // it isn't. Observed rather than delegated because the window is kept
        // alive across closes (`isReleasedWhenClosed` is false) and reused, so
        // there is no deinit to hang this off.
        DeviceController.shared.tuningWindowOpen = true
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: created, queue: .main
        ) { _ in
            Task { @MainActor in DeviceController.shared.tuningWindowOpen = false }
        }
        window = created
    }
}

private struct TuningView: View {
    @ObservedObject private var tuning = ArtworkTuning.shared
    @ObservedObject private var controller = DeviceController.shared
    @Environment(\.colorScheme) private var scheme

    /// Loaded here rather than borrowed from `PopoverView`, which keeps its copy
    /// in `@State` — so this window works whether or not the popover is open.
    @State private var artwork: Artwork?
    @State private var copied = false
    @State private var note: String?
    @State private var stripWidth: CGFloat = 920

    private static let swatchGap: CGFloat = 10
    /// Four columns, four gaps and the divider between the source and the
    /// renders.
    private var swatchSide: CGFloat {
        max((stripWidth - Self.swatchGap * 4 - 1) / 4, 44)
    }

    private var corner: ArtworkPalette.Corner? { artwork?.palette.corner }

    var body: some View {
        // **The previews are pinned; only the values scroll.**
        //
        // Every slider below changes what the strip shows, and scrolling the
        // one you're dragging out of sight is the one thing this window must
        // not do. Two scroll views would have been worse — the eye would have
        // to find which one moved.
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                previews
                measurements
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 14)
            Divider()
            values
        }
        // Behind-window vibrancy, so the swatches' own glass has something real
        // to sample. `.popover` deliberately — the same material the thing being
        // judged is made of.
        .background { WindowBackdrop().ignoresSafeArea() }
        .task(id: controller.status?.albumArtURL) {
            guard let url = controller.status?.albumArtURL else {
                artwork = Artwork.fallback
                return
            }
            // Falls back on a failed download too, not just a missing URL —
            // an unreachable host and no host at all are the same thing to
            // look at.
            artwork = await Artwork.load(from: url) ?? Artwork.fallback
        }
    }

    private var values: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                thresholds

                // **The same range on both, and a wide one.** The two were
                // asymmetric — light lifted, dark pulled down — which encoded
                // an assumption about which direction each appearance needs
                // into the control itself, so the other direction couldn't be
                // tried even to rule it out.
                group("Exposure", "additive · 0 leaves the image alone") {
                    toneMap($tuning.exposureOnLight, "Light mode", -3...3)
                    toneMap($tuning.exposureOnDark, "Dark mode", -3...3)
                }
                // **To 5, not 2.5.** Every category was tuned hard against
                // the old ceiling, which is what a range being too small looks
                // like from the inside: the value stops reporting what was
                // wanted and starts reporting where the slider ended.
                group("Contrast", "multiplicative · 1 leaves the image alone") {
                    toneMap($tuning.punchOnLight, "Light mode", 0.5...5)
                    toneMap($tuning.punchOnDark, "Dark mode", 0.5...5)
                }
                group("Saturation ceiling", "per stop, by that stop's brightness") {
                    ceiling($tuning.saturationOnLight, "Light mode")
                    ceiling($tuning.saturationOnDark, "Dark mode")
                }
                group("Vibrance", "boost per stop · headroom-proportional") {
                    vibrance($tuning.vibranceOnLight, "Light mode")
                    vibrance($tuning.vibranceOnDark, "Dark mode")
                }
                group("Tint opacity", "the sampled gradient") {
                    toneMap($tuning.tintOpacityOnLight, "Light mode", 0...1)
                    toneMap($tuning.tintOpacityOnDark, "Dark mode", 0...1)
                }
                group("Watermark opacity", "the cover itself, over the tint") {
                    toneMap($tuning.watermarkOpacityOnLight, "Light mode", 0...0.5)
                    toneMap($tuning.watermarkOpacityOnDark, "Dark mode", 0...0.5)
                }
                }
                // **The sliders only, not the row below them.** Read-only while
                // the committed values are up, because an edit made against
                // them would belong to neither set — but disabling the whole
                // scroll view took the buttons with it, and the only way back
                // out of the comparison is one of those buttons.
                .disabled(tuning.showing == .current)

                HStack(spacing: 8) {
                    // **A/B, not a revert.** Two sets of values on the same
                    // cover is the only way to tell whether an afternoon
                    // improved anything; holding them side by side is
                    // impossible, so alternating in place is the next best
                    // thing. Latest is disabled when there is nothing to go
                    // back to, which is also how the window says "unchanged".
                    Button("Current") { tuning.show(.current) }
                        .disabled(tuning.showing == .current)
                    Button("Latest") { tuning.show(.latest) }
                        .disabled(tuning.showing == .latest || !tuning.hasChanges)
                    Button("Discard") { discard() }
                        .disabled(!tuning.hasChanges)
                    Button("Overwrite…") { overwrite() }
                        .disabled(tuning.showing == .current)
                    // `#filePath` only resolves on the machine this was built
                    // on; the clipboard works everywhere.
                    //
                    // A glyph, because it is the one button here that isn't a
                    // decision — the other four each change what the app looks
                    // like or what is on disk, and a word next to each of them
                    // was giving this the same weight. The checkmark is the
                    // whole acknowledgement; a label saying "Copied" would put
                    // the word back two seconds after removing it.
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(tuning.generatedSource, forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "document.on.document")
                    }
                    .help("Copy the generated ArtworkDefaults.swift")
                    Spacer()
                }
                if tuning.showing == .current {
                    // Says out loud what the greyed-out sliders imply. Coming
                    // back to a window left in this mode, "why won't anything
                    // move" is a much easier question to have answered than
                    // asked.
                    Text("Showing the committed values — read-only. "
                         + "Press Latest to get back to this session's.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                Text("Overwrite rewrites larc/Presets/ArtworkDefaults.swift, so a "
                     + "session ends in a diff. Sampling — grid, saturation floor, "
                     + "hue distance — isn't there: it runs during the download, off "
                     + "the main thread, so it stays compile-time in ArtworkPalette.swift.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func stops(_ appearance: ColorScheme) -> some View {
        if let artwork {
            HStack(spacing: 5) {
                ForEach(Array(artwork.palette.resolvedStops(for: appearance).enumerated()),
                        id: \.offset) { _, stop in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(ArtworkPalette.color(stop))
                        .frame(width: 13, height: 13)
                        .overlay {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.25))
                        }
                    Text(String(format: "s %.2f  b %.2f", stop.saturation, stop.brightness))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .environment(\.colorScheme, appearance)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(appearance == .dark ? Color.black : Color.white,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }

    /// One prompt, where Overwrite gets two — proportionate to what is lost.
    ///
    /// Overwrite destroys a file in the checkout, which git can give back.
    /// This destroys a session's judgement calls, which nothing can; but it is
    /// also the ordinary way to start again, so making it laborious would be
    /// its own kind of wrong.
    private func discard() {
        let alert = NSAlert()
        alert.messageText = "Discard this session's changes?"
        alert.informativeText = "Every value goes back to what is committed in "
            + "ArtworkDefaults.swift."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        tuning.discardChanges()
    }

    /// **Two prompts, and the second one names the file.**
    ///
    /// This writes into the checkout — over whatever is in that file, including
    /// values someone committed deliberately and anything not yet committed at
    /// all. One dialog trains you to dismiss it; the second states the path and
    /// asks again, which is the only part that makes a slip unlikely rather
    /// than merely acknowledged.
    private func overwrite() {
        let first = NSAlert()
        first.messageText = "Overwrite ArtworkDefaults.swift?"
        first.informativeText = "The values in the source file are replaced with "
            + "the ones on screen. Anything in that file that hasn't been committed "
            + "is lost."
        first.addButton(withTitle: "Continue")
        first.addButton(withTitle: "Cancel")
        guard first.runModal() == .alertFirstButtonReturn else { return }

        let second = NSAlert()
        second.alertStyle = .critical
        second.messageText = "Write to \(ArtworkTuning.sourceURL.path)?"
        second.informativeText = "This can't be undone from here — only from git."
        second.addButton(withTitle: "Overwrite")
        second.addButton(withTitle: "Cancel")
        guard second.runModal() == .alertFirstButtonReturn else { return }

        note = tuning.writeToSource()
        Task {
            try? await Task.sleep(for: .seconds(5))
            note = nil
        }
    }

    // MARK: Previews

    /// The source on the left, both appearances on the right.
    ///
    /// **Two strips rather than one.** Every value here is split by appearance,
    /// so judging one at a time meant switching the system theme to see the
    /// other half of what was being tuned. Each row forces its own
    /// `colorScheme`, which the material honours as well as the maths.
    ///
    /// **The cover appeared twice and the grid not at all.** A second copy of
    /// the same picture says nothing — the layers differ by appearance, the
    /// source doesn't. The slot goes to the 16×16 sample grid instead, which is
    /// the thing every number on this window is computed from and the only part
    /// of the pipeline that was previously invisible. The divider marks the
    /// split: left is what the app read, right is what it drew.
    @ViewBuilder
    private var previews: some View {
        if let artwork {
            HStack(spacing: Self.swatchGap) {
                VStack(spacing: Self.swatchGap) {
                    swatch { artwork.image.resizable().scaledToFill() }
                    swatch { SampleGrid(palette: artwork.palette) }
                }
                Divider().frame(height: swatchSide * 2 + Self.swatchGap)
                VStack(spacing: Self.swatchGap) {
                    strip(.light)
                    strip(.dark)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // **Measured, so the swatches can be square.**
            //
            // Cover art is 1:1 and `.scaledToFill` covers, so any frame that
            // isn't square crops it — the same derivation the popover's
            // watermark is built on. Letting the swatches take a flexible width
            // and a fixed height quietly zoomed every cover and cut its edges
            // off. A side computed from the real width keeps them square at any
            // window size; the outer `maxWidth` is what stops the measurement
            // chasing its own result.
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: StripWidth.self, value: geo.size.width)
                }
            }
            .onPreferenceChange(StripWidth.self) { stripWidth = $0 }
        } else {
            Text("Play something with cover art to see it here.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// **No captions on any of this.** "Light" over a strip of light glass and
    /// "Watermark" under a watermark both restate what the eye already has, and
    /// six labels cost more vertical space than the measurements they were
    /// sitting above. Order is fixed — watermark, tint, the two together — and
    /// learned in one glance.
    @ViewBuilder
    private func strip(_ appearance: ColorScheme) -> some View {
            HStack(spacing: Self.swatchGap) {
                swatch { watermark(appearance) }
                swatch {
                    ZStack {
                        tint(appearance)
                        mockPill
                    }
                }
                swatch {
                    ZStack {
                        tint(appearance)
                        watermark(appearance)
                        mockNowPlaying
                    }
                }
            }
            // Sets the appearance for the mock content as well as the layers:
            // `.primary` and `.secondary` resolve from here, so the two strips
            // carry larc's own label colours — dark on the light one, white on
            // the dark one — without either being restated as a literal.
            .environment(\.colorScheme, appearance)
    }

    @ViewBuilder
    private func watermark(_ appearance: ColorScheme) -> some View {
        let t = tone(appearance)
        artwork?.image
            .resizable()
            .scaledToFill()
            .contrast(t.contrast)
            .brightness(t.brightness)
            .opacity(watermarkOpacity(appearance))
    }

    @ViewBuilder
    private func tint(_ appearance: ColorScheme) -> some View {
        if let artwork {
            LinearGradient(
                colors: artwork.palette.colors(for: appearance),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(tintOpacity(appearance))
        }
    }

    /// **The popover's own material behind each swatch**, not a checkerboard.
    ///
    /// A checkerboard says "this part is transparent", which is true and
    /// useless: nothing in the app is ever seen against one. These layers are
    /// always over glass, and glass is what decides whether a 0.1 watermark
    /// reads at all — so the preview has to be over the same thing.
    ///
    /// One honest limit: the window's backdrop blurs whatever is actually
    /// behind the window, so both strips sample the *same* desktop. The
    /// swatch's own glass and every value above it still respond to the strip's
    /// appearance, but a light desktop will sit under the dark strip too. Move
    /// the window over something dark to judge that half properly.
    private func swatch(@ViewBuilder content: () -> some View) -> some View {
            Color.clear
                // Square, and sized from the window rather than by a constant:
                // square because the cover is, and from the window because the
                // two right-hand swatches carry real controls now and a pill
                // and a transport row need every point available.
                .frame(width: swatchSide, height: swatchSide)
                .glassBackground(cornerRadius: 8)
                .overlay { content() }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// **Real components over the layers, not a colour on its own.**
    ///
    /// A tint at 0.45 looks fine as a rectangle and can still be the reason a
    /// pill's white glyph stops reading, or a subtitle drops below legible.
    /// These two swatches are where that gets judged, so they use the app's own
    /// pill and the app's own now-playing type rather than an approximation.
    private var mockPill: some View {
        LarcPill(title: "Test", systemImage: LarcIcon.controls) {}
            // Capped at what the popover would give it rather than filling the
            // swatch. Past ~220 a swatch is wider than the popover, and a pill
            // stretched beyond 210 is being judged at a width it can never have.
            .frame(maxWidth: Metrics.contentWidth)
            .padding(.horizontal, 6)
    }

    private var mockNowPlaying: some View {
        VStack(spacing: 1) {
            Text("Test Title").font(.headline)
            Text("Test Subtitle").font(.subheadline).foregroundStyle(.secondary)
            Image(systemName: LarcIcon.pause)
                .font(.system(size: 20))
                .padding(.top, 2)
            HStack {
                Text("0:12")
                Spacer(minLength: 8)
                Text("3:45")
            }
            .font(LarcUI.subtitleFont.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .frame(maxWidth: Metrics.contentWidth)
        .padding(.horizontal, 6)
    }

    private func tone(_ appearance: ColorScheme) -> ArtworkPalette.Tone {
        guard let corner else { return .init(brightness: 0, contrast: 1) }
        return ArtworkPalette.tone(for: appearance, corner: corner)
    }

    private func tintOpacity(_ appearance: ColorScheme) -> Double {
        guard let corner else { return 0 }
        let map = appearance == .dark ? tuning.tintOpacityOnDark : tuning.tintOpacityOnLight
        return map.value(for: corner)
    }

    private func watermarkOpacity(_ appearance: ColorScheme) -> Double {
        guard let corner else { return 0 }
        let map = appearance == .dark
            ? tuning.watermarkOpacityOnDark : tuning.watermarkOpacityOnLight
        return map.value(for: corner)
    }

    // MARK: Measurements

    @ViewBuilder
    private var measurements: some View {
        if let artwork, let corner {
            // **The measurements, and nothing derived from them.** A second
            // line used to print this cover's exposure, contrast and tint
            // opacity — every one of which is on a slider a few rows down, and
            // only ever for whichever appearance the system happened to be in,
            // never both strips. The three numbers here are the ones with no
            // other home: the two the carets are positioned from, and how many
            // colours survived the saturation floor to reach the gradient.
            // **Two `Text`s concatenated, not markdown.** Only a literal is
            // parsed as markdown; the moment `**…**` is built by appending a
            // formatted string it becomes a plain `String` and the asterisks
            // are just characters. Weight applied per-run says the same thing
            // and can't silently stop working.
            (Text(corner.label).fontWeight(.semibold)
                + Text(String(format: " · luminance %.3f · contrast %.3f · %d stops",
                              artwork.palette.luminance,
                              artwork.palette.contrast,
                              artwork.palette.colors(for: scheme).count)))
                .font(.callout.monospacedDigit())
            // **What the gradient actually ended up as.** Every knob on this
            // window converges here, and a stop pinned at brightness 1.00 with
            // saturation sitting exactly on the ceiling is the signature of
            // exposure and contrast having eaten the whole range — at which
            // point vibrance can't move anything and looks broken. Printed for
            // both appearances, since a value can be fine on one and pinned on
            // the other.
            HStack(spacing: 12) {
                stops(.light)
                stops(.dark)
            }
        }
    }

    /// **One track per spectrum, two thumbs on it.**
    ///
    /// These four numbers are not four settings — they're two pairs of *band
    /// edges* on two spectrums, and four separate tracks said the opposite.
    /// Reading whether "mid" was wide or narrow meant comparing two knob
    /// positions on two different rails; here it's the lit segment between the
    /// thumbs.
    private var thresholds: some View {
        group("Categories", "each track is one spectrum, split into three") {
            RangeSlider(
                lower: Binding(get: { Double(tuning.darkMidSplit) },
                               set: { tuning.darkMidSplit = CGFloat($0) }),
                upper: Binding(get: { Double(tuning.midLightSplit) },
                               set: { tuning.midLightSplit = CGFloat($0) }),
                title: "Luminance",
                bands: ("dark", "mid", "light"),
                at: (artwork?.palette.luminance).map(Double.init)
            )
            RangeSlider(
                lower: Binding(get: { Double(tuning.flatMidSplit) },
                               set: { tuning.flatMidSplit = CGFloat($0) }),
                upper: Binding(get: { Double(tuning.midBusySplit) },
                               set: { tuning.midBusySplit = CGFloat($0) }),
                title: "Contrast",
                bands: ("flat", "mid", "busy"),
                at: (artwork?.palette.contrast).map(Double.init)
            )
        }
    }

    // MARK: Controls

    @ViewBuilder
    private func group(
        _ title: String, _ note: String?, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title).font(.headline)
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            content()
        }
    }

    @ViewBuilder
    private func toneMap(
        _ map: Binding<ArtworkPalette.ToneMap>, _ title: String,
        _ range: ClosedRange<Double>
    ) -> some View {
        // **Only this cover's category is shown.** Nine per map times four maps
        // times two appearances is seventy-two sliders, of which one matters;
        // the eight-slider version already buried the live one. Both appearances
        // stay visible so the other mode can be set without switching, with the
        // inactive one dimmed.
        let active = (scheme == .dark) == title.hasPrefix("Dark")
        if let corner {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption)
                    .frame(width: 74, alignment: .leading)
                    .foregroundStyle(.secondary)
                slider(binding(map, corner), corner.label, range)
            }
            .opacity(active ? 1 : 0.4)
        }
    }

    private func binding(
        _ map: Binding<ArtworkPalette.ToneMap>, _ which: ArtworkPalette.Corner
    ) -> Binding<Double> {
        Binding(get: { map.wrappedValue[which] }, set: { map.wrappedValue[which] = $0 })
    }

    @ViewBuilder
    private func ceiling(
        _ value: Binding<ArtworkPalette.SaturationCeiling>, _ title: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            slider(Binding(get: { Double(value.wrappedValue.atDark) },
                           set: { value.wrappedValue.atDark = CGFloat($0) }),
                   "dark stop", 0...1)
            slider(Binding(get: { Double(value.wrappedValue.atBright) },
                           set: { value.wrappedValue.atBright = CGFloat($0) }),
                   "bright stop", 0...1)
        }
    }

    @ViewBuilder
    private func vibrance(
        _ value: Binding<ArtworkPalette.Vibrance>, _ title: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            slider(Binding(get: { Double(value.wrappedValue.atDark) },
                           set: { value.wrappedValue.atDark = CGFloat($0) }),
                   "dark stop", 0...1)
            slider(Binding(get: { Double(value.wrappedValue.atBright) },
                           set: { value.wrappedValue.atBright = CGFloat($0) }),
                   "bright stop", 0...1)
        }
    }

    private func slider(
        _ value: Binding<Double>, _ label: String, _ range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .frame(width: 74, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospacedDigit())
                .frame(width: 38, alignment: .trailing)
        }
    }
}


/// Two thumbs on one track, cutting a spectrum into three named bands.
///
/// **There is no stock range slider**, and the pair of plain `Slider`s this
/// replaces was actively misleading: two edges of one spectrum drawn as two
/// unrelated settings on two rails, so the width of "mid" — the thing being
/// set — was never on screen at all. Here it is the lit segment.
///
/// Hand-built controls are otherwise avoided in this project; the standing rule
/// against one is about the popover's volume slider, where a stock `Slider`
/// does the job. This is a developer window and there is nothing to reach for.
private struct RangeSlider: View {
    @Binding var lower: Double
    @Binding var upper: Double
    let title: String
    let bands: (String, String, String)
    /// Where this cover actually measures, ticked on the track — so a threshold
    /// can be dragged to just miss or just catch the cover in front of you.
    var at: Double?

    private let knob: CGFloat = 16
    private let trackHeight: CGFloat = 4
    /// Below this a band is too narrow for its name; the marker and the
    /// numbers still say where it is.
    private let labelMinimum: CGFloat = 32
    private let markerHeight: CGFloat = 6

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .frame(width: 74, alignment: .leading)
            GeometryReader { geo in
                let usable = max(geo.size.width - knob, 1)
                let x: (Double) -> CGFloat = { knob / 2 + CGFloat($0) * usable }
                VStack(spacing: 2) {
                    // **Above the track, not on it.** A tick drawn among the
                    // thumbs disappears exactly when it matters most — the
                    // moment the cover's score sits near a threshold, which is
                    // the moment you're dragging that threshold. Its own row
                    // can't be occluded.
                    marker(x)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.15))
                            .frame(height: trackHeight)
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(x(upper) - x(lower), 0), height: trackHeight)
                            .offset(x: x(lower))
                        thumb($lower, x: x(lower), usable: usable, upTo: upper)
                        thumb($upper, x: x(upper), usable: usable, from: lower)
                    }
                    .frame(height: knob)
                    bandLabels(x)
                }
                // The drag reads the pointer's position on the *track*, not
                // inside the thumb — a thumb's own space travels with it, so
                // every drag would read as a few points from centre and the
                // knob would crawl.
                .coordinateSpace(name: Self.track)
            }
            .frame(height: markerHeight + 2 + knob + 2 + 11)
            Text(String(format: "%.2f  %.2f", lower, upper))
                .font(.caption.monospacedDigit())
                .frame(width: 62, alignment: .trailing)
        }
    }

    private static let track = "track"

    private func thumb(
        _ value: Binding<Double>, x: CGFloat, usable: CGFloat,
        from low: Double = 0, upTo high: Double = 1
    ) -> some View {
        Circle()
            .fill(.white)
            .shadow(radius: 1, y: 0.5)
            .frame(width: knob, height: knob)
            .offset(x: x - knob / 2)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.track))
                    .onChanged { drag in
                        let raw = Double((drag.location.x - knob / 2) / usable)
                        // Clamped here rather than left to `ArtworkTuning`'s
                        // didSet: the thumbs stop against each other instead of
                        // shoving, so dragging past the other one can't quietly
                        // move a value nobody was touching.
                        value.wrappedValue = min(max(raw, min(low, high)), max(low, high))
                    }
            )
    }

    @ViewBuilder
    private func marker(_ x: @escaping (Double) -> CGFloat) -> some View {
        ZStack(alignment: .leading) {
            if let at {
                Caret()
                    .fill(Color.primary)
                    .frame(width: 9, height: markerHeight)
                    .offset(x: x(min(max(at, 0), 1)) - 4.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: markerHeight)
    }

    private func bandLabels(_ x: @escaping (Double) -> CGFloat) -> some View {
        ZStack(alignment: .leading) {
            band(bands.0, from: 0, to: lower, x)
            band(bands.1, from: lower, to: upper, x)
            band(bands.2, from: upper, to: 1, x)
        }
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 11)
    }

    @ViewBuilder
    private func band(
        _ name: String, from: Double, to: Double, _ x: @escaping (Double) -> CGFloat
    ) -> some View {
        let width = x(to) - x(from)
        if width >= labelMinimum {
            Text(name)
                .frame(width: width)
                .offset(x: x(from))
        }
    }
}

/// The 16×16 grid the palette is computed from, cell for cell.
///
/// **Every cell, in place, unmodified.** Not the toned samples the tint is
/// drawn from — this is the input, and its whole job is to let a number be
/// checked against the picture: whether the accent really did survive as its
/// own cells rather than averaging into the background, why a cover measured
/// 0.647 luminance, where the p10 and p90 of the contrast spread live.
///
/// The chosen stops are ringed. Those one to three cells are the entire
/// gradient, and which cells won is the least obvious step in the pipeline —
/// saturation × brightness, minus anything under the saturation floor, minus
/// anything within 0.08 hue of an earlier pick.
private struct SampleGrid: View {
    let palette: ArtworkPalette

    var body: some View {
        Canvas { context, size in
            let n = palette.gridSide
            let side = size.width / CGFloat(n)
            for (index, cell) in palette.cells.enumerated() {
                guard let cell else { continue }
                let origin = CGPoint(
                    x: CGFloat(index % n) * side,
                    y: CGFloat(index / n) * side
                )
                // A half-point of overlap: at fractional cell sizes, exact
                // rects leave hairlines of the background between them and the
                // grid reads as a mesh rather than as a picture.
                let rect = CGRect(
                    origin: origin,
                    size: CGSize(width: side + 0.5, height: side + 0.5)
                )
                context.fill(Path(rect), with: .color(Color(
                    hue: cell.hue,
                    saturation: cell.saturation,
                    brightness: cell.brightness
                )))
                if palette.chosen.contains(index) {
                    // Two rings, light over dark, because a single ring in
                    // either colour vanishes against half the covers there are.
                    context.stroke(Path(rect.insetBy(dx: -0.5, dy: -0.5)),
                                   with: .color(.black), lineWidth: 2.5)
                    context.stroke(Path(rect.insetBy(dx: -0.5, dy: -0.5)),
                                   with: .color(.white), lineWidth: 1.5)
                }
            }
        }
    }
}

/// A downward wedge: where the current cover measures on a `RangeSlider`.
private struct Caret: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Behind-window vibrancy for the tuning window.
///
/// A representable, which this project bans **inside the popover** — that ban is
/// about `NSPopover`, whose rendering was blanked twice by AppKit surgery. This
/// is an ordinary window, and there is no SwiftUI equivalent: `.regularMaterial`
/// blends within the window, and the whole point here is to blend with what is
/// behind it.
private struct WindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}


/// The width the preview strips actually get, so their swatches can be square.
private struct StripWidth: PreferenceKey {
    static let defaultValue: CGFloat = 920
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
#endif
