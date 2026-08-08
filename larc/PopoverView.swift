import SwiftUI
import ServiceManagement

/// Every layout measurement in the popover, defined once.
///
/// **One margin, and one padding that reaches back out past it.**
///
///   - `contentMargin` (14) — where content starts, and where nearly everything
///     lines up: row icons, the device picker, the track text, dividers,
///     section captions.
///   - `backgroundPadding` (7) — how far a *background* extends beyond the
///     content it sits behind, so a hover fill has breathing room without
///     shifting the icons. Applied as negative padding, which grows a view
///     outward, so a 212pt row draws a 226pt fill.
///
/// Only three things use the second: a row's hover fill, the accessibility
/// warning box, and the marquee's fade. Everything else simply sits on the
/// margin. There used to be a `highlightGutter` (7) as well, but nothing ever
/// read it — it existed only to be subtracted from `contentMargin`, so the
/// subtraction is gone and the padding is stated directly.
///
/// Internal rather than file-private: the shared components in
/// `Presets/Components.swift` lay out against the same numbers, and duplicating
/// them there is what let three row styles drift apart.
enum Metrics {
    static let popoverWidth: CGFloat = 240

    /// From the popover's edge to where content begins.
    ///
    /// 15 rather than a rounder 14 because it's what makes the control grid come
    /// out whole. With a 6pt gap it leaves 210pt of content, which divides into
    /// four 48pt pills and three 66pt tiles exactly — and 48 halves and quarters
    /// cleanly for a capsule's radius and a pill's leading inset. At 14 the same
    /// grid gives 47, whose quarter is 11.75.
    static let contentMargin: CGFloat = 15
    /// How far a background reaches past the content it backs, on each side.
    /// Matches `LarcUI.gridSpacing`, so the air around a hover fill is the same
    /// measure as the air between two controls.
    static let backgroundPadding: CGFloat = 6
    /// The same idea vertically. Small because rows are already tall enough.
    static let highlightVerticalBleed: CGFloat = 2
    /// Closer to the popover's own (much larger) radius than a tighter value,
    /// which read as noticeably sharper next to it.
    static let highlightCornerRadius: CGFloat = 10

    /// Asymmetric: the extra headroom is for the device picker's "P ␣" badge,
    /// which draws above the picker's bounds and would otherwise land on the
    /// popover's pointer arrow.
    static let topGutter: CGFloat = 26
    static let bottomGutter: CGFloat = 14
    static let rowSpacing: CGFloat = 10

    static var contentWidth: CGFloat { popoverWidth - contentMargin * 2 }
    /// Track text is allowed a highlight's reach, so its fade ends where a
    /// highlight's edge would. MarqueeText insets its glyphs by the same bleed,
    /// putting the first character back on the content gutter.
    static var trackTextWidth: CGFloat { contentWidth + backgroundPadding * 2 }

    static let transportHitbox: CGFloat = 45

    /// Ceiling for a sub-screen's scrolling content — **as much of the screen as
    /// there is**, rather than a flat number.
    ///
    /// It was 420, picked to be safe on a 13-inch display. That made screens
    /// scroll that had no need to: the icon picker fits comfortably until its
    /// duplicate-name error appears, at which point it crossed 420 and grew a
    /// scrollbar, which then shifted every row sideways. The popover had room to
    /// simply get taller and didn't take it.
    ///
    /// **Nothing is chosen here.** The screen decides, and everything subtracted
    /// from it is derived from the parts that actually occupy the space.
    ///
    /// This briefly had a `min(max(…, 320), 620)` around it. Both bounds were
    /// wrong. The 620 was picked by eye — a number with no argument behind it,
    /// which is the thing this codebase keeps deleting. The 320 floor was worse
    /// than arbitrary: on a display too short for it, clamping *up* would size
    /// the scroll area larger than the space available and push the popover off
    /// the bottom of the screen — the floor would cause the problem it looks
    /// like it prevents.
    ///
    /// **Two limits, and they are different kinds of thing.** The smaller wins.
    ///
    ///   - *Fit*: what the screen has. `visibleFrame` already excludes the menu
    ///     bar and the dock, so this is genuinely usable height on whatever
    ///     machine it's running on. A hard constraint — exceed it and the
    ///     popover runs off the bottom.
    ///   - *Proportion*: how tall a 240pt-wide column may be before it stops
    ///     reading as a popover. A soft constraint, but a real one: unclamped,
    ///     a 27-inch display gives a 1290pt popover, which is a sidebar.
    ///
    /// Expressed as a multiple of the popover's own width rather than a chosen
    /// height, so it's an argument about shape rather than a number picked by
    /// eye — and it follows `popoverWidth` if that ever changes.
    static var subScreenMaxHeight: CGFloat {
        let fits = (NSScreen.main?.visibleFrame.height ?? 800) - subScreenChrome
        let proportionate = popoverWidth * maxAspect - subScreenChrome
        return max(min(fits, proportionate), 0)
    }

    /// How many times its own width the popover may be tall.
    ///
    /// 2 → 480pt at the current width, so a sub-screen holds about 8 preset
    /// rows before it scrolls. The only taste in this file's height maths; every
    /// other number is measured or derived.
    static let maxAspect: CGFloat = 2

    /// Width a **legacy** scroller takes out of a scroll view's content area.
    ///
    /// Zero for overlay scrollers, which float and reserve nothing.
    ///
    /// **`.scrollIndicators(.hidden)` does not remove this**, which cost three
    /// attempts to learn: it hides *indicators*, and a legacy scroller is a
    /// persistent control rather than an indicator. Hiding them suppressed the
    /// overlay scroller — harmless, it took no space anyway — and left the
    /// legacy one, which is the one that does.
    ///
    /// So the scroller stays, in whichever style the OS asked for, and the
    /// header is inset to match the content instead. Every Mac app behaves this
    /// way; the bug was only that our header didn't move with it.
    static var scrollerWidth: CGFloat {
        guard NSScroller.preferredScrollerStyle == .legacy else { return 0 }
        return NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    }

    /// Everything a sub-screen spends before its scrolling area gets any.
    ///
    /// Summed from the metrics that draw each piece rather than estimated, so
    /// changing the header or the margin moves this automatically.
    static var subScreenChrome: CGFloat {
        contentMargin           // above the header
        + headerHeight
        + rowSpacing            // header to divider
        + 1                     // the divider
        + popoverFrame
    }

    /// The header row's height: the back button's hitbox, which is taller than
    /// the title text and therefore sets it.
    static let headerHeight: CGFloat = 22

    /// What `NSPopover` draws around our content — the arrow plus the frame's
    /// own vertical inset, top and bottom.
    ///
    /// **The one number here that is estimated**, because AppKit doesn't publish
    /// it and it can't be measured without running. Erring high costs a little
    /// unused height on a tall screen; erring low lets the popover reach the
    /// dock. If a long screen ever runs too close to the bottom, this is the
    /// only value to change.
    static let popoverFrame: CGFloat = 40

    /// How long the Controls pill will wait for a device to identify itself
    /// before opening anyway. Long enough for a device that's merely slow,
    /// short enough that one which is never going to answer doesn't hold a
    /// press hostage.
    static let controlsWaitTimeout: TimeInterval = 6


    /// Breathing room above and below whatever is in the band. `rowSpacing`
    /// already separates it from its neighbours, so this only keeps the content
    /// off the band's own edges.
    static let statusGapPadding: CGFloat = 2

    /// Fixed-height band between the track text and the transport row.
    ///
    /// Two jobs. It's the breathing room that spaces out the middle of the
    /// section, and it's where the seek bar appears — which is why its height is
    /// *fixed* rather than a padding: a bar that comes and goes with the source
    /// (radio has no length) must not change the section's height, or the
    /// divider moves under the watermark.
    ///
    /// **It used to reserve room for the unreachable warning too, and doesn't
    /// now** — that warning is a glyph beside the device picker, where it can
    /// appear and disappear horizontally and cost no height anywhere. Reserving
    /// a whole row for something the width of an icon was the more complicated
    /// answer to the same problem.
    ///
    /// Measured budget it feeds, top of the picker to the divider: picker 24,
    /// track text 40, **this band**, transport 45, volume 20, four
    /// `rowSpacing` of 10 between them, 2 + 10 of track-text padding,
    /// `transportTopPadding` 8, and 2.5 + 20 of volume padding — 231.5 with
    /// this at 20, of which 211.5 is picker to the bottom of the volume
    /// slider.
    ///
    /// **That 199.5 is the invariant**, and nothing about the device's state
    /// can move it now. Losing the device *entirely* still drops everything
    /// below the picker, which is a state rather than a warning.
    ///
    /// 20 = a `Slider`'s own height plus `statusGapPadding` either side. Kept at
    /// exactly what the warning used to make it, so removing the warning moved
    /// nothing.
    static var statusGapHeight: CGFloat { statusGapPadding * 2 }

    /// A little extra air under the volume row, so the slider isn't crowded
    /// against the divider below it.
    ///
    /// This does grow the section, and so nudges the divider down by the same
    /// amount — but it changes nothing about the artwork. The watermark's height
    /// is derived from its own width (square, full-bleed), never from the
    /// section, and its 28pt fade means its bottom edge isn't a landmark
    /// anything is aligned to.
    static let volumeBottomPadding: CGFloat = 2.5

    /// Watermark is full-bleed: no gutter, edge to edge.
    static var watermarkWidth: CGFloat { popoverWidth }
}

struct PopoverView: View {
    @ObservedObject var controller = DeviceController.shared
    @ObservedObject var keyTap = MediaKeyTap.shared
    @ObservedObject var hotkeys = PopoverHotkeys.shared
    @ObservedObject var navigation = PopoverNavigation.shared
    @ObservedObject var settings = DeviceSettingsModel.shared
    /// Redraws the artwork layers while the tuning window's sliders move.
    @ObservedObject var tuning = ArtworkTuning.shared
    /// Measured height of the current sub-screen's content, so the popover
    /// hugs a short screen and scrolls a tall one.
    ///
    /// **Starts at the maximum, not zero.** At zero the first layout pass gives
    /// the scroll view a zero-height frame, and it settles on a scroll offset
    /// computed in that state — so a tall screen opened already scrolled, with
    /// its first section above the top edge. Starting full-height and shrinking
    /// to fit never produces an offset, because the content always fits during
    /// the pass that decides one.
    @State private var subScreenHeight: CGFloat = Metrics.subScreenMaxHeight
    /// Bumped when the scroller style changes, purely to force a re-layout —
    /// `NSScroller.preferredScrollerStyle` is a plain class property, so SwiftUI
    /// has nothing to observe and would keep the old gutter until something
    /// unrelated invalidated the view.
    @State private var scrollerStyleToken = 0
    /// Where a seek drag currently points, or nil when not dragging. Holds the
    /// bar still against the 2s poll for the length of the gesture.
    @State private var seekTarget: Double?
    /// Whether the main screen's tint has faded in yet.
    ///
    /// **Starts false on every appearance.** `NSPopover` animates its own window
    /// when the content's size changes, so arriving at a shorter screen leaves a
    /// gap between the new content and the old window height — and the main
    /// screen's tint, being full-height, filled it. That read as the screen
    /// stretching to reveal a wallpaper.
    ///
    /// Fading the tint in after the resize has settled fixes exactly that, and
    /// nothing else. The alternative was `popover.animates = false`, which cures
    /// it by disabling AppKit's window animation for the whole app — a global
    /// answer to a local problem, and it took the open and close animations with
    /// it.
    @State private var tintVisible = false
    @AppStorage(SettingsKeys.mediaKeysEnabled) private var mediaKeysEnabled = false
    // Volume Step now lives on the Controls screen and is stored per device —
    // see VolumeStepStore. It isn't read here any more.
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    /// Just the device picker, driven only by the "P" hotkey. Deliberately a
    /// single Bool rather than a reprise of the old FocusItem enum — nothing
    /// else in the popover tracks or resets focus, and no ring is drawn by us.
    /// The picker is NSPopUpButton-backed, so it shows AppKit's own ring when
    /// focused, which is the point: it's the only feedback that "P" worked.
    @FocusState private var deviceFocused: Bool

    /// The current album art and the palette sampled from it — one download,
    /// both layers. Nil when there's no art, or loading failed; artwork is
    /// decoration, so failure just means no tint and no watermark. Loaded by
    /// nowPlayingSection's .task.
    @State private var artwork: Artwork?

    /// Start of the current marquee cycle, shared by the title and subtitle so
    /// they stay frame-locked. Reset when the text changes; shifted forward when
    /// motion resumes, so a pause freezes rather than restarts.
    @State private var marqueeAnchor = Date()
    /// When motion froze, or nil while running. See marqueeFrozen.
    @State private var marqueeFrozenAt: Date?

    /// The tint's brightness band follows the appearance — see
    /// ArtworkPalette.colors(for:). Light mode needed a higher band; at the
    /// shared one its low end read as muddy against a near-white popover.
    @Environment(\.colorScheme) private var colorScheme

    // Step options moved to VolumeStepStore.options alongside the storage.

    /// The navigation shell: the main screen, or whichever sub-screen is on
    /// the stack, sliding horizontally between them.
    ///
    /// Width is pinned for every screen. Height is free to change on
    /// navigation — a popover grows downward from its anchor, so that reads
    /// fine, whereas a width change shifts it sideways and `MarqueeText`
    /// measures against a fixed `popoverWidth`.
    var body: some View {
        // **Top-aligned.** A ZStack centres its children, so while its height
        // animates between two screens the incoming one is clipped at *both*
        // ends — and since the tint is a gradient, clipping the top moved which
        // part of the gradient landed there. That's the top and bottom colours
        // appearing to change on the way in. Anchored at the top, the gradient's
        // start is fixed and only the bottom is clipped, which is the end that
        // is arriving anyway.
        ZStack(alignment: .top) {
            // **No animation at all — an instant swap.**
            //
            // Every artefact in this popover's navigation came from the same
            // cause: an animated change means *both* screens exist for its
            // duration, so the ZStack is as tall as the taller of them. That
            // produced, in order, a tint that shrank on the way out, a tint
            // whose top and bottom colours moved on the way in, and a short
            // screen stretching to the main screen's height and revealing its
            // wallpaper underneath. Each fix addressed a symptom; the cause was
            // always the overlap.
            //
            // Sliding only the main screen wouldn't help — the overlap is what
            // costs, not the direction of travel. Nor would pinning the
            // artwork's geometry: the popover itself is the thing resizing.
            //
            // So the swap is instantaneous, and the popover is only ever the
            // height of one screen. Fixed edges were tried before this and read
            // wrong sub-to-sub anyway (both sides used the same edge, so the
            // screens passed through each other), and a direction-dependent
            // transition can't work because SwiftUI bakes a view's *removal*
            // transition when it is created.
            if let current = navigation.current {
                subScreen(current)
                    // **Refuses to be compressed.** The ZStack animates its
                    // height between the two screens, and a child without this
                    // accepts the shrinking proposal — which is what made the
                    // tint squeeze inwards from top and bottom on the way to a
                    // shorter screen, and why going to a *taller* one looked
                    // fine. `.clipped()` on the ZStack hides the overflow, so
                    // keeping the ideal height costs nothing.
                    .fixedSize(horizontal: false, vertical: true)
                    // Keyed on the whole stack, not on "is there a sub-screen":
                    // pushing from one sub-screen to another changes neither
                    // that condition nor the view type, so SwiftUI reused the
                    // view and swapped its contents with no transition at all.
                    .id(navigation.stack)
            } else {
                mainScreen
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: Metrics.popoverWidth)
        .clipped()
        .onReceive(NotificationCenter.default.publisher(
            for: NSScroller.preferredScrollerStyleDidChangeNotification
        )) { _ in scrollerStyleToken += 1 }
    }

    /// The column a legacy scroller occupies on *this* screen, or zero.
    ///
    /// Only when the content actually overflows, because that's when AppKit
    /// shows the scroller. The header uses the same value, so the two move
    /// together and the divider never disagrees with the rows beneath it —
    /// which was the whole visible symptom.
    ///
    /// Read through `scrollerStyleToken` so changing the system setting, or
    /// unplugging a mouse under "Automatically", re-lays this out immediately
    /// rather than at the next unrelated redraw.
    private var scrollerGutter: CGFloat {
        _ = scrollerStyleToken
        return subScreenHeight > Metrics.subScreenMaxHeight ? Metrics.scrollerWidth : 0
    }

    /// What's left of the trailing margin once the scroller's column has taken
    /// its share of it. Zero when a legacy scroller is present, since its column
    /// is already `contentMargin` wide.
    private var contentTrailing: CGFloat {
        max(Metrics.contentMargin - scrollerGutter, 0)
    }

    /// Whether anything that needs the device is worth offering.
    ///
    /// A device has to be both selected and answering. `reachable` is the poll's
    /// verdict, so it stays false for as long as the device is actually
    /// unreachable rather than flashing once and clearing — which is what made
    /// the old "Reading device…" line useless: it appeared and vanished on every
    /// press, when the honest state was permanent.
    private var deviceUsable: Bool {
        controller.selectedDevice != nil && controller.reachable
    }

    /// Controls was pressed before its settings had arrived: the pill waits in
    /// place, and the push happens when they do.
    ///
    /// **Waiting on the main screen beats opening an empty one.** Navigating
    /// immediately meant arriving at a screen whose every control was either
    /// blank or, worse, showing a fallback — six unlabelled outputs the hardware
    /// may not have. Holding the press for one round trip costs a moment; the
    /// alternative costs trust in what the screen says.
    @State private var awaitingControls = false


    @ViewBuilder
    private func subScreen(_ screen: PopoverScreen) -> some View {
        // Spacing 0 at this level, deliberately. Any gap here would sit between
        // the divider and the scroll view's *viewport*, so scrolling content
        // would vanish that far below the separator instead of passing under
        // it. The header keeps its own spacing in the inner stack; the scroll
        // view's top gutter lives inside its content, below.
        VStack(alignment: .leading, spacing: 0) {
            // Header and divider carry their own gutter; the scroll view below
            // spans the full popover width so its content's highlights can
            // bleed outward. A gutter on the whole stack would inset the scroll
            // view too, and clip them again.
            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                header(for: screen)
                Divider()
            }
            // Plain margins on both sides. The scroller's column *is* the
            // trailing margin for the content below (see `contentTrailing`), so
            // the divider at a plain `contentMargin` already ends level with it.
            .padding(.horizontal, Metrics.contentMargin)
            // Scrolls past a ceiling rather than growing without limit: a
            // preset editor carries three grids, a slider and a delete row, and
            // an unbounded popover would run off a laptop screen. The header
            // stays above it, so "back" is never scrolled away from.
            // Indicators left on. `showsIndicators: false` hides the scroller
            // *always*, not just at rest — so a long screen gave no sign it
            // could scroll at all. Whether it overlays or takes up space is a
            // system setting (Appearance → Show scroll bars), and overriding
            // that on one app's popover isn't ours to do.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                    switch screen {
                    case .presets:
                        PresetsScreen()
                    case .controls:
                        ConfigureScreen()
                    case .configurePresets:
                        ConfigurePresetsScreen()
                    case .editPreset(let id):
                        PresetEditScreen(presetID: id)
                    case .iconPicker(let id):
                        IconPickerScreen(presetID: id)
                    case .about:
                        AboutScreen()
                    case .queue:
                        QueueScreen()
                    #if LARC_DEV
                    case .dev:
                        DevScreen()
                    #endif
                    }
                }
                // Pinned rather than left to fill: inside a ScrollView the
                // horizontal proposal is unbounded, so grids sized to their own
                // ideal width and overflowed the popover on both sides.
                //
                // **Always the full content width, scroller or not.** The
                // scroller's column comes out of the trailing margin rather than
                // out of the content, so a screen doesn't reflow the moment it
                // becomes long enough to scroll.
                .frame(width: Metrics.contentWidth, alignment: .leading)
                // Gutter *inside* the scroll view, so a row's hover fill can
                // bleed into it the way it does on the main screen. With the
                // padding outside, the scroll view clipped at the content width
                // and every highlight stopped square at the text.
                //
                // Vertical works the same way and for the same reason: outside,
                // it insets the *viewport*, so content clipped short of the
                // popover's bottom edge with a band of dead tint beneath it,
                // and short of the divider at the top. Inside, the viewport
                // spans divider to popover edge, content clips exactly there,
                // and scrolling to either end reveals the gutter as breathing
                // room. One margin on all four sides — the top and bottom used
                // to be rowSpacing and bottomGutter, which was two arbitrary
                // numbers where the horizontal edges already had a principled
                // one.
                .padding(.leading, Metrics.contentMargin)
                // **The scroller's column doubles as the trailing margin**, so
                // the gap from content to the popover's edge is `contentMargin`
                // either way. Adding a full margin *on top of* the column put
                // ~20pt between the last tile and the scrollbar against 15 on
                // the left, which is the asymmetry that showed on screen.
                .padding(.trailing, contentTrailing)
                .padding(.vertical, Metrics.contentMargin)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: SubScreenHeightKey.self, value: proxy.size.height
                        )
                    }
                }
            }
            // `.visible`, not `.automatic`. Both defer to the OS for *style* and
            // for the fade — an overlay scroller still appears on scroll and
            // hides at rest — but `.automatic` let SwiftUI decide whether to
            // offer one at all, and under "When scrolling" it decided not to.
            //
            // **Constant, never toggled.** This briefly read
            // `isNavigating ? .hidden : .visible`, to stop a scroller riding
            // along with a sliding screen. But `push` sets that flag *before*
            // the incoming screen appears, so every scroll view was born with
            // indicators hidden — and switching to `.visible` 0.3s later does
            // not make AppKit reconfigure an overlay scroller. It then stayed
            // missing until the first rubber-band bounce forced a relayout,
            // which is why it only appeared after scrolling to an edge. A
            // legacy scroller was unaffected because it occupies layout space
            // and so gets rebuilt anyway.
            .scrollIndicators(.visible)
            .frame(width: Metrics.popoverWidth)
            // Measured rather than .fixedSize: fixedSize and maxHeight fight,
            // which clipped the content short of the popover's own bottom edge.
            .frame(height: min(subScreenHeight, Metrics.subScreenMaxHeight))
            .onPreferenceChange(SubScreenHeightKey.self) { subScreenHeight = $0 }
            // Back to full height whenever the screen changes, so the incoming
            // screen is measured from a state that fits rather than inheriting
            // the outgoing one's height and starting scrolled.
            .onChange(of: navigation.stack) {
                subScreenHeight = Metrics.subScreenMaxHeight
            }
        }
        // Top only, and the same margin as every other edge — the bottom gutter
        // moved inside the scroll view's content so the viewport can reach the
        // popover's own bottom edge. This one is above the *header*, which
        // doesn't scroll, so it stays out here.
        .padding(.top, Metrics.contentMargin)
        .frame(width: Metrics.popoverWidth)
        // No tint here — `body` paints it once, outside every screen, so it
        // fills the popover rather than stopping at this screen's height.
    }

    /// The header shows the preset's own icon, colour and name once you're
    /// inside one — the row you tapped becomes the title, which is what makes
    /// the navigation feel like one continuous surface.
    @ViewBuilder
    private func header(for screen: PopoverScreen) -> some View {
        switch screen {
        case .editPreset(let id), .iconPicker(let id):
            if let preset = PresetStore.shared.preset(id: id) {
                LarcScreenHeader(
                    symbol: preset.symbol,
                    title: preset.name,
                    tint: preset.tint.color
                ) { navigation.pop() }
            } else {
                LarcScreenHeader(symbol: screen.symbol, title: screen.title) {
                    navigation.pop()
                }
            }
        default:
            LarcScreenHeader(symbol: screen.symbol, title: screen.title) {
                navigation.pop()
            }
        }
    }

    private var mainScreen: some View {
        VStack(spacing: Metrics.rowSpacing) {
            // .zIndex(1) because this section carries hotkey badges.
            //
            // Badges are overlays, so they're drawn as part of their row — and a
            // VStack draws its children in declaration order, meaning a later
            // Divider() sibling painted *over* the badges of an earlier row
            // wherever they overlapped. The volume badges sit closest to the
            // divider below them and were the visible case. .zIndex inside
            // hotkeyHint can't fix this: it only orders a view against siblings
            // in the same container, and the badge's container is the row, not
            // this VStack.
            nowPlayingSection
                .zIndex(1)

            // No divider above: these two continue the same subject as the
            // controls they sit under — the device — rather than starting a new
            // one. Controls first, because it's where you go to change what's
            // happening now; presets are the saved shortcut for having done it.
            HStack(spacing: LarcUI.gridSpacing) {
                // **Both disabled when the device can't be reached.** Everything
                // behind them is a round trip: Controls reads and writes device
                // settings, a preset applies them. Letting you in to a screen
                // that can only fail is worse than saying so at the door — and
                // it was actively misleading, since Controls would breathe for
                // six seconds and then open anyway.
                LarcPill(
                    title: PopoverScreen.controls.title,
                    systemImage: PopoverScreen.controls.symbol,
                    disabled: !deviceUsable,
                    isWaiting: awaitingControls,
                    bouncesOnPress: false
                ) {
                    openControls()
                }
                // No subtitle, unlike Scan below. A count of presets isn't news
                // — it doesn't change unless you change it — so it bought a
                // second line of height for a number nobody needs at a glance,
                // and made this pill sit taller than Controls beside it.
                LarcPill(
                    title: PopoverScreen.presets.title,
                    systemImage: PopoverScreen.presets.symbol,
                    disabled: !deviceUsable
                ) {
                    navigation.push(.presets)
                }
            }

            // No Queue pill until PlayQueue1 is actually wired — see ROADMAP.
            // `QueueScreen` and its navigation case stay, so restoring it is
            // one pill rather than a rebuild of the screen.

            // larc's own settings. The two toggles are binary, so they take the
            // round shape; Scan is an action with something to report, so it
            // takes a pill — sized to exactly half the content width so its
            // left edge lines up with Presets above it. Left to fill whatever
            // remained, it landed a few points wide of that and read as
            // misaligned.
            HStack(spacing: LarcUI.gridSpacing) {
                // The two toggles share the half the pill doesn't take, evenly.
                // Left at their intrinsic 34pt they sat in a pool of empty
                // space with a gap before Scan, which read as a layout mistake
                // rather than as breathing room.
                HStack(spacing: LarcUI.gridSpacing) {
                    LarcCircleToggle(
                        symbol: LarcIcon.mediaKeys,
                        label: "Media Keys",
                        isOn: mediaKeysEnabled && keyTap.accessibilityGranted,
                        disabled: pendingPermission,
                        action: toggleMediaKeys
                    )
                    .frame(maxWidth: .infinity)
                    LarcCircleToggle(
                        symbol: LarcIcon.launchAtLogin,
                        label: "Launch at Login",
                        isOn: launchAtLogin
                    ) {
                        setLaunchAtLogin(!launchAtLogin)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(width: LarcUI.pillDouble)

                // Waiting, not disabled. Dimming the whole capsule to 0.4 muted
                // the glyph along with the label, which is backwards — the
                // glyph is the part still saying something. The press is a
                // no-op while a scan is running, so nothing needs blocking.
                LarcPill(
                    title: controller.scanning ? "Scanning…" : "Scan",
                    systemImage: LarcIcon.scanNetwork,
                    subtitle: lastScannedSubtitle,
                    isWaiting: controller.scanning,
                    bouncesOnPress: false
                ) {
                    controller.rescan()
                }
                .frame(width: LarcUI.pillDouble)
            }

            // Pending state: capture is switched on but Accessibility hasn't
            // come through yet — the notice disappears (and the control
            // re-enables) by itself once the 3 s permission poll sees the
            // grant; no restart needed.
            if pendingPermission {
                accessibilityWarning
            }
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(LarcUI.subtitleFont)
                    .foregroundStyle(LarcUI.errorColor)
            }

            HStack(spacing: LarcUI.gridSpacing) {
                LarcPill(
                    title: PopoverScreen.about.title,
                    systemImage: PopoverScreen.about.symbol
                ) {
                    navigation.push(.about)
                }
                LarcPill(title: "Quit", systemImage: LarcIcon.quit) {
                    NSApp.terminate(nil)
                }
                .hotkeyHint("⌘Q", hotkeys: hotkeys, edge: .top)
            }

            #if LARC_DEV
            // Only compiled into a `./build.sh --dev` build.
            HStack(spacing: LarcUI.gridSpacing) {
                LarcPill(
                    title: PopoverScreen.dev.title,
                    systemImage: PopoverScreen.dev.symbol
                ) {
                    navigation.push(.dev)
                }
                Spacer(minLength: 0).frame(width: LarcUI.pillDouble)
            }
            #endif
        }
        .padding(.horizontal, Metrics.contentMargin)
        // The held press, released. Watching the model rather than awaiting a
        // call means a load already in flight when the press happened counts —
        // there's no second request, and no way to end up waiting on one that
        // finished a moment before.
        .onChange(of: settings.isReadyForControls) {
            guard awaitingControls, settings.isReadyForControls else { return }
            awaitingControls = false
            navigation.push(.controls)
        }
        // Bounded, because a device that never answers must not leave the pill
        // breathing indefinitely. Going anyway rather than reporting an error:
        // the screen states its own case honestly now that a failed
        // identification is nil rather than a blank identity, so it says
        // "Reading device…" instead of inventing outputs.
        .task(id: awaitingControls) {
            guard awaitingControls else { return }
            try? await Task.sleep(for: .seconds(Metrics.controlsWaitTimeout))
            guard !Task.isCancelled, awaitingControls else { return }
            awaitingControls = false
            navigation.push(.controls)
        }
        // Asymmetric: 26 at the top rather than 14, to make room for the device
        // picker's "P ␣" badge at distance 22. The badge draws above the
        // picker's bounds, so without the headroom it overlaps the popover's
        // pointer arrow. Costs 12pt of empty space when hints are hidden, which
        // is the price of the badge not colliding with the chrome.
        .padding(.top, Metrics.topGutter)
        .padding(.bottom, Metrics.bottomGutter)
        .frame(width: Metrics.popoverWidth)
        // **The tint belongs to this screen, not to the popover.**
        //
        // It was on the ZStack that swaps the screens, which is sized to
        // whichever screen is showing — so leaving the main screen animated the
        // ZStack's height down to the sub-screen's, and the gradient shrank
        // inwards from the top and bottom as it faded. Entering the main screen
        // looked fine only because it grows into place behind an opaque screen.
        //
        // Here it is sized to the main screen, which is the only screen it
        // applies to anyway (the tint is sampled from what's playing). It fades
        // with its own screen and never resizes.
        .background { popoverTint.opacity(tintVisible ? 1 : 0) }
        // Applied here rather than on `nowPlayingSection`: the tint is this
        // screen's background and the watermark is that section's, so only a
        // modifier at this level covers both.
        .animation(.easeOut(duration: Self.artworkFade), value: artwork)
        // Keyed separately, because `Artwork` compares by URL alone — the logo
        // dimming is the same artwork in a different state, which that
        // comparison is right to call unchanged and this would otherwise snap.
        .animation(.easeOut(duration: Self.artworkFade), value: atRest)
        .onAppear {
            tintVisible = false
            Task {
                try? await Task.sleep(for: .seconds(Self.tintFadeDelay))
                withAnimation(.easeOut(duration: Self.artworkFade)) {
                    tintVisible = true
                }
            }
        }
        .onDisappear { tintVisible = false }
        // Deliberately NO .focusEffectDisabled() here.
        //
        // It only suppresses focus effects SwiftUI draws itself, which in this
        // popover means the .plain-styled Buttons and nothing else. Picker,
        // Toggle, and Slider are SwiftUI API backed by NSPopUpButton, NSSwitch,
        // and NSSlider internally, and those draw their own AppKit focus rings
        // from NSView.focusRingType — a separate mechanism the SwiftUI
        // environment value cannot reach. So the modifier suppressed five of
        // nine controls and was silently ignored by the rest, which is *worse*
        // than either extreme: Tab still moved through everything, but only
        // some stops were visible.
        //
        // Rings on Tab are correct, especially with keyboard navigation enabled
        // in System Settings. The actual complaint was a ring appearing on open
        // without being asked for, and that's a first-responder problem, fixed
        // in AppDelegate.popoverDidShow. Goal is "no rings until you ask", not
        // "no rings ever".
        .onAppear {
            // The popover's view identity persists across open/close (menu
            // bar window style), so @State isn't re-initialized each time —
            // without this, toggling Launch at Login off in System Settings
            // (Login Items) would leave the switch showing stale "on".
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Settings rows

    /// True while capture is switched on but Accessibility hasn't come
    /// through yet: the toggle stays ON (that's the user's intent) but
    /// disabled, since it can't actually do anything until granted.
    private var pendingPermission: Bool {
        mediaKeysEnabled && !keyTap.accessibilityGranted
    }

    /// Registers or unregisters the login item, keeping the stored flag in step
    /// with what the system actually reports — a failure leaves the control
    /// showing the truth rather than the attempt.
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func toggleMediaKeys() {
        mediaKeysEnabled.toggle()
        if mediaKeysEnabled && !keyTap.accessibilityGranted {
            keyTap.requestPermission()
        }
    }

    /// Opens Controls, or waits on the pill until there's something to open.
    ///
    /// `loadIfNeeded` rather than `force`: a load is usually already in flight
    /// from device selection, and re-requesting would only duplicate it. It does
    /// start one in the case that matters — an earlier attempt that failed,
    /// which now clears its own guard precisely so this can retry.
    private func openControls() {
        if settings.isReadyForControls {
            navigation.push(.controls)
        } else {
            awaitingControls = true
            settings.loadIfNeeded()
        }
    }

    private var lastScannedSubtitle: String? {
        guard !controller.scanning, let last = controller.lastScanAt else { return nil }
        let minutes = Int(Date().timeIntervalSince(last) / 60)
        switch minutes {
        case 0: return "Just now"
        case 1: return "A minute ago"
        case 2...10: return "\(minutes) minutes ago"
        default: return nil
        }
    }

    // MARK: - Device & playback

    /// What the unreachable glyph and its gap take out of the picker's cap.
    private var warningInset: CGFloat {
        guard !controller.reachable, controller.selectedDevice != nil else { return 0 }
        return LarcUI.iconSingle + LarcUI.rowSpacing
    }

    /// What the picker is currently showing — the same string the menu button
    /// draws, so measuring it gives the width it needs.
    private var pickerTitle: String {
        controller.selectedDevice?.name ?? "Choose a device"
    }

    private var devicePicker: some View {
        // **The warning sits beside the picker, not in a row of its own.**
        //
        // It used to live in the seek band, which had to be a fixed height
        // purely so that its appearing couldn't push the divider down under the
        // watermark. A glyph next to the control it is about appears and
        // disappears horizontally, costs no height anywhere, and says which
        // device it means — three things the reserved row never managed.
        HStack(spacing: LarcUI.rowSpacing) {
            pickerControl
            if !controller.reachable, controller.selectedDevice != nil {
                Image(systemName: LarcIcon.deviceUnreachable)
                    .font(.system(size: LarcUI.iconSingle))
                    .foregroundStyle(LarcUI.cautionColor)
                    // The words the icon replaces, kept where they cost no
                    // layout — and required, since a glyph alone is not a
                    // message to anyone using VoiceOver.
                    .help("Device not responding")
                    .accessibilityLabel("Device not responding")
                    .transition(.opacity)
            }
        }
        .animation(.default, value: controller.reachable)
        // One badge, not two: "P" and Space are sequential steps (focus, then
        // open), not alternative shortcuts for the same action the way J/⌘←
        // are. Two boxes would read as "either of these works".
        // ␣ is U+2423 OPEN BOX, the conventional space-key glyph — SF Symbols
        // has no plain space-bar symbol.
        //
        // Pushed further out than the default 14, since this is the topmost row
        // and the badge had nothing between it and the popover's pointer arrow.
        // Requires the matching .padding(.top, 26) in `body` — the badge draws
        // outside the picker's bounds, so without that headroom it lands on the
        // popover's own chrome.
        .hotkeyHint("P ␣", hotkeys: hotkeys, distance: 22)
        .onReceive(hotkeys.$focusDeviceRequestID.dropFirst()) { _ in
            deviceFocused = true
        }
    }

    private var pickerControl: some View {
        // Plain SwiftUI Picker. An NSPopUpButton-wrapped NSViewRepresentable
        // was tried here once and twice corrupted the whole popover's
        // rendering into a giant blank rectangle overlapping the menu bar
        // (2026-07-25, both a custom sizeThatFits override AND a plain
        // .fixedSize() on the representable triggered it). Don't wrap an
        // AppKit control in this popover without being able to see it render
        // live first.
        Group {
            if controller.devices.isEmpty {
                // No dropdown at all when there's nothing to pick — a plain
                // label instead of a Picker, so there's no chevron/arrow
                // implying an interaction that isn't possible.
                Text("No devices found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("Device", selection: Binding(
                    get: { controller.selectedID ?? "" },
                    set: { controller.selectedID = $0.isEmpty ? nil : $0 }
                )) {
                    // Shown until a device is confirmed for this network —
                    // never a silently auto-picked one (see
                    // DeviceController.mergeDevices).
                    if controller.selectedID == nil {
                        Text("Choose a device").tag("")
                    }
                    ForEach(controller.devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .labelsHidden()
                .focused($deviceFocused)
                // Sized to the *selected* name, not hugged.
                //
                // A full-width menu button against a 240pt popover reads as a
                // form field; sized to the device's name it reads as a title you
                // can change, which is what it is. `.fixedSize()` was here for a
                // long time and never achieved that — see LarcUI.popUpWidth for
                // why it can't. Capped at the content width so a very long
                // device name doesn't push past the popover.
                // Capped short of the full content width while the warning is
                // showing, so a long device name pushes the picker rather than
                // the glyph off the edge.
                .frame(width: min(LarcUI.popUpWidth(for: pickerTitle),
                                  Metrics.contentWidth - warningInset))
                // The width now depends on which device is chosen, so it moves
                // on every switch. Animated, since a control that changes size
                // instantly reads as a relayout rather than as the same control
                // holding a different word.
                .animation(.default, value: pickerTitle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// The band in the middle of the section, and what fills it.
    ///
    /// Fixed height whether or not anything is in it, so the section — and
    /// therefore the divider's position — never moves.
    ///
    /// A full-opacity artwork thumbnail lived here briefly and was reverted: the
    /// tint and the watermark already carry the art, and a third legible copy in
    /// the middle of the controls was one too many.
    /// Position, and the warning, in one fixed-height band.
    ///
    /// **Fixed height, still.** It replaced `statusGap`, which reserved room so
    /// that the "not responding" warning appearing couldn't change the section's
    /// height. The same applies now with more reasons: a seek bar comes and goes
    /// with the source (radio has no length), and the popover must not resize
    /// when a track changes.
    ///
    /// Two states, one height: a seekable track shows the bar, anything else
    /// shows nothing. Unreachable used to be a third — it is a glyph beside the
    /// device picker now, where it costs no height at all.
    private var seekRow: some View {
        ZStack {
            if controller.reachable, let status = controller.status, status.isSeekable {
                seekBar(status)
            }
        }
        .frame(height: Metrics.statusGapHeight)
    }

    @ViewBuilder
    private func seekBar(_ status: PlayerStatus) -> some View {
        let duration = status.duration ?? 0
        HStack(spacing: 6) {
            Text(Self.clock(seekTarget ?? status.position ?? 0))
            // Dragging holds a local target, so the bar follows the pointer
            // instead of being yanked back by the next poll — the same
            // slider-fight guard the volume row needs, for the same reason.
            Slider(
                value: Binding(
                    get: { seekTarget ?? status.position ?? 0 },
                    set: { seekTarget = $0 }
                ),
                in: 0...duration,
                onEditingChanged: { editing in
                    guard !editing, let target = seekTarget else { return }
                    controller.seek(to: target)
                    seekTarget = nil
                }
            )
            // Counts down, because what's left is the more useful number once
            // you know how long a track is.
            Text("-" + Self.clock(duration - (seekTarget ?? status.position ?? 0)))
        }
        .font(LarcUI.subtitleFont.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    /// m:ss, and h:mm:ss only when there are hours — a leading "0:" on every
    /// track would be noise.
    private static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// Device picker and everything about the current track, over a wash of
    /// the album art.
    ///
    /// An earlier version put the artwork beside the controls as a 96pt tile,
    /// the way the system Now Playing panel does — but that needs width the
    /// popover doesn't have (three 45pt transport buttons plus gaps is 159pt
    /// on its own) and pushed it to 360pt, which read as bloated. As a
    /// backdrop the art costs no layout at all.
    private var nowPlayingSection: some View {
        VStack(spacing: Metrics.rowSpacing) {
            devicePicker

            if controller.selectedDevice != nil {
                trackText
                    .padding(.top, Self.trackTextTopPadding)
                    .padding(.bottom, Self.trackTextBottomPadding)
                // Replaces the fixed `statusGap` band. The seek bar reports
                // position where that only reserved room for a warning, and it
                // still houses the warning, so nothing lost its home.
                seekRow
                // **Hidden, not removed.** On a passthrough input there is no
                // stream for these to act on, but the popover's height must not
                // depend on which input is selected -- `.hidden()` keeps the
                // frame and drops the hit testing.
                transportButtons
                    .padding(.top, Self.transportTopPadding)
                    .opacity(transportUsable ? 1 : 0)
                    .disabled(!transportUsable)
                    .accessibilityHidden(!transportUsable)
                volumeRow
                    .padding(.bottom, Self.volumeBottomPadding)
            }
        }
        .background(alignment: .top) { artworkWatermark }
        // Keyed to the URL: a new track re-downloads and re-samples, no artwork
        // clears both layers.
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
        // Animation lives on `mainScreen` now, so it reaches the tint too.
    }

    /// Height of the artwork wash. Deliberately less than the popover's 240pt
    /// width, so it reads as a banner across the top rather than a tall block —
    /// letting it size itself to the section made it taller than it was wide.
    private static let artworkWashHeight: CGFloat = 140
    /// Long enough for the popover's window resize to finish before the tint
    /// starts appearing, short enough not to read as a delay of its own.
    private static let tintFadeDelay: TimeInterval = 0.05

    /// **One duration for every artwork change, both layers.**
    ///
    /// The tint and the watermark are two views of the same picture, so they
    /// have to move together — and they didn't: the 0.35s on `nowPlayingSection`
    /// reached the watermark, which is that section's background, but not the
    /// tint, which is the *main screen's*. So a track change cross-faded the
    /// texture and snapped the colour. (`popoverTint` carries a
    /// `.transition(.opacity)`, but a transition only runs on insertion and
    /// removal, and one artwork replacing another is neither.)
    ///
    /// Now shared by both, and by the fade-in after a screen appears — the same
    /// picture arriving, whichever way it arrives.
    private static let artworkFade: TimeInterval = 0.4

    /// Air above the transport row and below the volume row, so the block of
    /// controls isn't crowded against the text above or the divider below.
    ///
    /// **20 was asked for on both; the top gives some of it back to the seek
    /// bar.** A seek bar costs height, and the popover is already the tallest
    /// thing that hangs from a menu bar. Taking it from the top keeps the volume
    /// row's breathing room, which is the one adjoining a divider.
    /// Air around the track text, on top of the `rowSpacing` already between it
    /// and its neighbours. The pair sums to 12, so moving weight from one to
    /// the other shifts the text without changing the section's height.
    private static let trackTextTopPadding: CGFloat = 2
    private static let trackTextBottomPadding: CGFloat = 10
    private static let transportTopPadding: CGFloat = 8
    private static let volumeBottomPadding: CGFloat = 20

    /// The sampled-colour gradient tints the WHOLE popover at this strength.
    /// Tint strength, from **two** properties of the cover and the appearance
    /// it's drawn on.
    ///
    /// The driver is contrast, not brightness:
    ///
    ///   - **Flat** art — dark or light, little variation — has nothing of its
    ///     own to look at, so the tint can be strong without competing.
    ///   - **Busy** art — a dark cover full of bright detail, or the reverse —
    ///     is already visually loud, so the tint drops back and blends.
    ///
    /// Brightness is the second axis, and it exists so each end can be tuned
    /// separately: a flat *black* cover and a flat *white* one both want a
    /// strong tint, but not necessarily the same one, and which is which
    /// depends on the appearance underneath.
    ///
    /// Four numbers per appearance, one per corner, interpolated bilinearly —
    /// so nothing sits on a threshold and a middling cover gets a middling
    /// strength. An earlier version had only the brightness axis, which is why
    /// it couldn't express any of this.
    @MainActor
    private static func tintOpacity(
        _ scheme: ColorScheme, corner: ArtworkPalette.Corner
    ) -> Double {
        let map = scheme == .dark
            ? ArtworkTuning.shared.tintOpacityOnDark
            : ArtworkTuning.shared.tintOpacityOnLight
        return map.value(for: corner)
    }


    /// Tint opacity lives in `ArtworkTuning` so it can be moved with sliders.
    /// The artwork itself is layered over that tint as a faint watermark. Two
    /// semi-transparent layers rather than one: the gradient carries the album's
    /// colour everywhere, the watermark adds a hint of its actual shape behind
    /// the controls.
    /// Per appearance, because the two grounds don't carry an image alike. On a
    /// near-white popover 0.08 is already visible; on a dark one the same value
    /// nearly disappears, since the art is being multiplied into a dark surface
    /// rather than a light one. Same reasoning as `ArtworkPalette`'s exposure,
    /// which is also split by appearance — and now by category too.
    ///
    /// **Read from `ArtworkTuning`, not stated here.** These were two constants
    /// while the tuning window drew its own sliders for them, so the sliders
    /// moved the preview and left the popover exactly where it was — the one
    /// layer on that window whose value could not be trusted.
    /// **The logo at rest is dimmed, a cover never is.**
    ///
    /// Gated on playback rather than on whether artwork exists, because the two
    /// answer different questions. A cover with no music behind it doesn't
    /// happen; the logo with no music behind it is the popover's most common
    /// state, since a menu bar app is opened while idle more often than not.
    /// Full strength there would have the app asserting "something is playing"
    /// whenever it wasn't.
    ///
    /// Desaturated as well as faded so it recedes rather than merely thins —
    /// a pale gold wash still reads as a colour choice, where a grey one reads
    /// as the absence of one.
    /// False on a passthrough input, where nothing exists for the buttons to
    /// act on. See `PlayerStatus.supportsTransport`.
    private var transportUsable: Bool {
        controller.status?.supportsTransport ?? true
    }

    private var atRest: Bool {
        guard let artwork, artwork.isFallback else { return false }
        return !(controller.status?.state.showsAsPlaying ?? false)
    }

    private var restingSaturation: Double { atRest ? Self.restingSaturation : 1 }
    private var restingOpacity: Double { atRest ? Self.restingOpacity : 1 }

    private static let restingSaturation: Double = 0.2
    private static let restingOpacity: Double = 0.4

    private var watermarkOpacity: Double {
        guard let artwork else { return 0 }
        let map = colorScheme == .dark
            ? tuning.watermarkOpacityOnDark
            : tuning.watermarkOpacityOnLight
        return map.value(for: artwork.palette.corner)
    }
    /// **Zero.** Tried at 6, 2, 1, 0.5 and 4 over several rounds. At 0.08
    /// opacity the art is already faint, and softening it as well removes the
    /// texture that is the only reason this layer exists — the gradient beneath
    /// carries the colour.
    private static let watermarkBlur: CGFloat = 0

    /// Exposure and contrast for the current artwork, from `ArtworkPalette` so
    /// the watermark and the tint are adjusted by the same numbers. Neutral when
    /// there's no artwork, though nothing draws in that case anyway.
    private var artworkTone: ArtworkPalette.Tone {
        guard let artwork else { return .init(brightness: 0, contrast: 1) }
        return ArtworkPalette.tone(for: colorScheme, corner: artwork.palette.corner)
    }
    /// Grown about its own centre. `.aspectRatio(.fill)` in a square frame is
    /// centred by construction, so this keeps the centre with no offset to go
    /// stale — expressed as points rather than a factor because "40 larger" is
    /// what was asked for and a factor would drift if the width changed.
    private static let watermarkOverhang: CGFloat = 2
    /// Matches `LarcUI.presetTileLarge`, the pill unit — the same curve the
    /// popover's own controls use, so the art doesn't introduce a third radius.
    private static let watermarkCornerRadius: CGFloat = 24
    /// Watermark is full-bleed — flush to the popover's top, left and right
    /// edges, no gutter, same reach as the tint underneath it.
    ///
    /// Square, because album art is 1:1 and the whole cover should show
    /// uncropped. `.aspectRatio(.fill)` scales to cover, so any frame that isn't
    /// square crops the image — at 226×198 it was losing 14pt off the top and
    /// bottom. Deriving the height from the width makes that impossible rather
    /// than something to notice later; `Metrics.transportTopSpacing` is what
    /// makes the section tall enough to accommodate it.
    private static var watermarkHeight: CGFloat { Metrics.watermarkWidth }
    /// Height of the fade-to-transparent band at the bottom, in points rather
    /// than as a fraction — the band stays this tall whatever the overall height
    /// becomes. Well before the divider the watermark is transparent enough that
    /// the divider's exact position no longer has to be reconciled with it.
    private static let watermarkFadeHeight: CGFloat = 48

    /// The sampled-colour gradient, filling the entire popover.
    ///
    /// Applied outside the content padding so it reaches every edge. Note it
    /// cannot reach the popover's *arrow*: that's drawn by AppKit's private
    /// NSPopoverFrame, not by this view, and no public API exposes it. The arrow
    /// stays the default material.
    @ViewBuilder
    private var popoverTint: some View {
        if let artwork {
            LinearGradient(
                colors: artwork.palette.colors(for: colorScheme),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .saturation(restingSaturation)
            .opacity(Self.tintOpacity(colorScheme, corner: artwork.palette.corner)
                     * restingOpacity)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }


    /// The album art itself, very faint, behind the picker/track/transport/volume
    /// block — a watermark over the flat tint rather than instead of it.
    ///
    /// Half a point of blur: 1pt and 2pt both washed out the texture that's the
    /// reason for having this layer at all, and 0 left JPEG detail slightly too
    /// crisp against the flat gradient underneath. The gradient supplies the
    /// colour; this pass only hints at the cover's shape — which is the point of
    /// layering two weak passes instead of pushing one harder.
    @ViewBuilder
    private var artworkWatermark: some View {
        if let artwork {
            artwork.image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(
                maxWidth: .infinity,
                minHeight: Self.watermarkHeight + Self.watermarkOverhang,
                maxHeight: Self.watermarkHeight + Self.watermarkOverhang
            )
            // Rounded now that it no longer bleeds to the popover's edges: at
            // full bleed the popover clipped its own corners and rounding this
            // too cut visible notches inside them, but an inset square needs
            // its own curve or it reads as a photo dropped on the surface.
            .clipShape(RoundedRectangle(cornerRadius: Self.watermarkCornerRadius,
                                       style: .continuous))
            .blur(radius: Self.watermarkBlur)
            // **Exposure before opacity.** Opacity alone can't make a near-black
            // cover visible on a light popover: more of it is a darker smudge,
            // so "more visible" and "brighter" pull apart. Lifting the image's
            // tones first turns a black cover into light-grey structure, which
            // then only needs a little opacity to read.
            //
            // Contrast is applied before brightness so it pivots around the
            // image's own mid-grey rather than around whatever brightness has
            // just shifted it to — otherwise raising exposure would flatten the
            // silhouette it is meant to reveal.
            .contrast(artworkTone.contrast)
            .brightness(artworkTone.brightness)
            .saturation(restingSaturation)
            .opacity(watermarkOpacity * restingOpacity)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 1 - Self.watermarkFadeHeight / Self.watermarkHeight),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // Grown symmetrically about the centre: half the overhang past each
            // horizontal edge, and lifted by the top gutter plus the same half
            // so the vertical growth is centred too. Offset, not padding —
            // padding would shrink the laid-out height as well as move it.
            .padding(.horizontal, -(Metrics.contentMargin + Self.watermarkOverhang / 2))
            .offset(y: -(Metrics.topGutter + Self.watermarkOverhang / 2))
            .allowsHitTesting(false)
        }
    }

    private static let titleFont = NSFont.preferredFont(forTextStyle: .headline)
    private static let subtitleFont = NSFont.preferredFont(forTextStyle: .subheadline)

    /// "Unknown" rather than "Not Playing" when the device *is* playing but
    /// won't say what.
    ///
    /// Plenty of sources give no metadata at all — a bare stream URL, some
    /// AirPlay senders, an analogue input — and "Not Playing" over audible
    /// music is simply wrong. The distinction is what the transport reports,
    /// not what the metadata does.
    private var titleText: String {
        // **An external source names itself, not its content.** On optical or
        // HDMI the device has audio and no idea what it is — and often a stale
        // copy of whatever it last played over the network, which is worse than
        // nothing because it reads as current. "Optical" is the whole truth
        // available, so it is what's shown.
        if let status = controller.status, status.isExternalSource {
            return status.input?.displayName ?? "External"
        }
        if let title = controller.status?.title { return title }
        return controller.status?.state.showsAsPlaying == true ? "Unknown" : "Not Playing"
    }

    /// Nothing under the title for an external source: the device's artist and
    /// album fields are stale there, and repeating the input's name would say it
    /// twice.
    private var subtitleText: String? {
        guard controller.status?.isExternalSource != true else { return nil }
        return controller.status?.subtitle
    }

    /// One shared cycle length for both lines: the longest scroll plus the
    /// pause. Each line still scrolls at the same constant speed, so a longer
    /// string takes longer and they finish at different moments — but both then
    /// wait out this period, so they pause and restart in step rather than
    /// drifting apart over time.
    private var trackTextCycle: Double {
        let title = MarqueeText.scrollDuration(
            text: titleText, nsFont: Self.titleFont, width: Metrics.trackTextWidth
        )
        let subtitle = subtitleText.map {
            MarqueeText.scrollDuration(
                text: $0, nsFont: Self.subtitleFont, width: Metrics.trackTextWidth
            )
        } ?? 0
        return MarqueeText.pause + max(title, subtitle)
    }

    /// Motion runs only when the popover is open *and* something is playing.
    /// Pausing the player pauses the scroll, leaving it mid-travel rather than
    /// snapping back — that's what `MarqueeText.frozenAt` is for.
    private var marqueeFrozen: Bool {
        !(controller.popoverOpen && controller.status?.state.showsAsPlaying == true)
    }

    /// Both lines' text as one value, to watch for changes.
    private var trackTextKey: String {
        "\(titleText)\u{1}\(subtitleText ?? "")"
    }

    private var trackText: some View {
        VStack(spacing: 1) {
            MarqueeText(
                text: titleText,
                nsFont: Self.titleFont,
                width: Metrics.trackTextWidth,
                anchor: marqueeAnchor,
                frozenAt: marqueeFrozenAt,
                cycleDuration: trackTextCycle
            )
            // Omitted entirely when there's no artist or album — devices send
            // placeholder junk rather than leaving fields empty, so this is nil
            // far more often than you'd expect. See LinkplayPlugin.placeholders.
            if let subtitle = subtitleText {
                MarqueeText(
                    text: subtitle,
                    nsFont: Self.subtitleFont,
                    width: Metrics.trackTextWidth,
                    anchor: marqueeAnchor,
                    frozenAt: marqueeFrozenAt,
                    cycleDuration: trackTextCycle
                )
                .foregroundStyle(.secondary)
            }
        }
        // Reserves both lines' height whether or not the subtitle exists, so
        // the popover doesn't change height between tracks.
        .frame(height: 40, alignment: .top)
        // Bleeds to the same x as the hover highlights and the warning box.
        // MarqueeText insets its text by exactly this much, so glyph one lands
        // back on the content edge and only the fade lives out here.
        .padding(.horizontal, -Metrics.backgroundPadding)
        // A new track restarts the cycle, so stepping through tracks faster than
        // the pause shows the beginning of every title. No `.id()` needed for
        // this any more — MarqueeText holds no state to reset.
        .onChange(of: trackTextKey) {
            marqueeAnchor = Date()
            if marqueeFrozenAt != nil { marqueeFrozenAt = Date() }
        }
        // Freeze and resume rather than reset: on resume the anchor moves forward
        // by however long motion was stopped, so the clock reads exactly what it
        // did when it stopped and travel continues from there.
        .onChange(of: marqueeFrozen) { _, frozen in
            if frozen {
                marqueeFrozenAt = Date()
            } else {
                if let frozenAt = marqueeFrozenAt {
                    marqueeAnchor += Date().timeIntervalSince(frozenAt)
                }
                marqueeFrozenAt = nil
            }
        }
        .onAppear {
            // The popover's view identity survives close/open, so without this a
            // reopen would resume a cycle from minutes ago.
            marqueeAnchor = Date()
            marqueeFrozenAt = marqueeFrozen ? Date() : nil
        }
    }

    /// `.loading` shows pause too — see PlayState.showsAsPlaying. A device
    /// buffering the next track is on its way to playing, and treating it as
    /// stopped was half of why the icon flipped twice per track change.
    private var showsPause: Bool {
        controller.status?.state.showsAsPlaying == true
    }

    private var transportButtons: some View {
        // Fixed frame on all three so the hit target is the same size for
        // prev/next as play/pause, even though play/pause's glyph is visually
        // larger — only the frame is equalized, not the icon sizes. 45×45
        // (28→56 doubled, then ×0.8 for the "reduce track controls to 80%"
        // pass = 44.8→45).
        //
        // The frame and .contentShape both live INSIDE each label, not on the
        // Button. With .buttonStyle(.plain) hit testing follows the label's
        // drawn content, so a frame applied outside the Button enlarged the
        // layout without enlarging the click target: TrianglePairIcon's
        // natural size is about one glyph (its offsets don't expand layout),
        // which left the real hitbox small and off-centre — clicks on the
        // inner triangle missed entirely. Same reason LarcRow sets
        // .contentShape on its own HStack.
        HStack(spacing: 12) {
            Button {
                controller.previousTrack()
            } label: {
                TrianglePairIcon(flipped: true, trigger: controller.previousTrackTrigger)
                    .frame(width: Metrics.transportHitbox, height: Metrics.transportHitbox)
                    .contentShape(Rectangle())
            }
            .hotkeyHint(["⌘←", "J"], hotkeys: hotkeys, distance: -1 * Metrics.backgroundPadding / 2)

            Button {
                controller.playPause()
            } label: {
                // Explicit shrink-out/grow-in transition (not a plain instant
                // symbol swap) keyed off status.state directly — that fires
                // identically whether the state changed via a click or a
                // hotkey. The Button itself still gives the native
                // press-darken feedback on a real click, same as before.
                ZStack {
                    if showsPause {
                        Image(systemName: LarcIcon.pause)
                            .transition(.scale(scale: 0.01).combined(with: .opacity))
                    } else {
                        Image(systemName: LarcIcon.play)
                            .transition(.scale(scale: 0.01).combined(with: .opacity))
                    }
                }
                // Keyed to the glyph, not to state. Keying it to state ran the
                // spring on transitions the glyph doesn't care about — e.g.
                // playing → loading — which is animation for no visible reason.
                .animation(.spring(response: 0.25, dampingFraction: 0.65), value: showsPause)
                // 1.5x .title2's ~22pt, then 80% for the overall track
                // controls resize (33 * 0.8 = 26.4).
                .font(.system(size: 26))
                .frame(width: Metrics.transportHitbox, height: Metrics.transportHitbox)
                .contentShape(Rectangle())
            }
            .hotkeyHint("K", hotkeys: hotkeys, distance: -1 * Metrics.backgroundPadding / 2)

            Button {
                controller.nextTrack()
            } label: {
                TrianglePairIcon(flipped: false, trigger: controller.nextTrackTrigger)
                    .frame(width: Metrics.transportHitbox, height: Metrics.transportHitbox)
                    .contentShape(Rectangle())
            }
            .hotkeyHint(["L", "⌘→"], hotkeys: hotkeys, distance: -1 * Metrics.backgroundPadding / 2)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .disabled(controller.selectedDevice == nil)
    }

    private var volumeRow: some View {
        HStack(spacing: 8) {
            Button { controller.toggleMute() } label: {
                // Sized by width like every other icon, and boxed in a fixed
                // 20×20 frame. The box matters here specifically: speaker.slash
                // and speaker.wave.2 have different proportions, and letting the
                // glyph set the button's height nudged the whole popover by a
                // couple of pixels on every mute toggle.
                LarcGlyph(
                    symbol: controller.status?.muted == true
                        ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    size: LarcUI.iconSingle
                )
                    // Width matches the volume number's frame on the far side
                    // (both 20) so the leading and trailing insets around the
                    // slider are equal — that's what centres the slider in the
                    // row, and so centres its hotkey badge under the play
                    // button. Height stays pinned at 20 for the mute-toggle
                    // layout stability noted above.
                    .frame(width: 20, height: 20)
            }
            // .plain with an explicit primary foreground, not .borderless.
            // A borderless button renders its glyph in the system control
            // colour, which sits lighter than the .primary used by every row
            // icon below — so the mute control read as a different weight from
            // the rest of the popover.
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .hotkeyHint("M", hotkeys: hotkeys, distance: 20)

            Slider(
                value: Binding(
                    get: { controller.displayVolume },
                    set: { controller.userSetVolume($0) }
                ),
                // The device's own ceiling, not a flat 100 — a device capped at
                // 40 should show 20 as half full, and its slider should reach
                // the end rather than stopping dead two-fifths along.
                in: 0...100,
                onEditingChanged: { controller.volumeDragChanged($0) }
            )
            .hotkeyHint(["↑ ↓", "− ="], hotkeys: hotkeys, edge: .top, distance: 2)

            Text("\(Int(controller.displayVolume))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                // 20, matching the mute button's width — see the note there.
                // Tight for "100" at caption monospaced-digit; verified rather
                // than assumed, since clipping would only show at max volume.
                .frame(width: 20, alignment: .trailing)
        }
        .padding(.bottom, Metrics.volumeBottomPadding)
    }

    private var accessibilityWarning: some View {
        // Icon on the left, text stacked to its right (not a Label) — same
        // reasoning as LarcRow: a Label's icon would sit at the VStack's
        // leading edge and drag the body text under the icon instead of
        // lining up with every other row's text-start position.
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: LarcIcon.warning)
                .frame(width: 16)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Accessibility Permission")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Enable Larc in System Settings")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Open System Settings") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
        }
        // Vertical-only content padding — no horizontal, so the icon lines
        // up at the same x as every other row's icon. The background bleeds
        // outward instead (same negative-padding trick as LarcRow's hover)
        // to give the box breathing room without shifting the icon/text.
        .padding(.vertical, 8)
        .background {
            // Flat 10% wash on every OS version, deliberately NOT glass.
            // `.glassEffect(.regular.tint(.orange))` was tried on macOS 26 and
            // renders as a near-solid saturated orange block, not a subtle
            // tint — it swamped the section and crushed the body text to
            // near-unreadable. Glass tint is not a low-opacity fill.
            RoundedRectangle(cornerRadius: Metrics.highlightCornerRadius)
                .fill(Color.orange.opacity(0.1))
                .padding(.horizontal, -Metrics.backgroundPadding)
                .padding(.vertical, -Metrics.highlightVerticalBleed)
        }
    }
}

/// One line of text that scrolls continuously when it's too wide to fit, and
/// sits still when it isn't.
///
/// Two copies of the string separated by `gap` are scrolled by exactly one
/// "lap" (`textWidth + gap`). At the end of a lap the second copy sits exactly
/// where the first began, so wrapping back to zero is invisible and the result
/// reads as one endless loop — the tail leaves on the left while the head is
/// already entering on the right, never a blank line between them. Approach
/// cribbed from joekndy/MarqueeText.
///
/// **The offset is a pure function of elapsed time, not an animation.** No
/// `@State`, no `withAnimation`, no Task. An earlier version gave each line its
/// own `withAnimation(.linear)`, which caused three separate bugs: the lines
/// drifted against each other, since two independent animation timelines don't
/// stay frame-locked (visible as jitter, and as one line seeming faster than the
/// other despite identical pt/s); pausing was impossible, because a running
/// SwiftUI animation can't be frozen; and a track change mid-scroll let SwiftUI
/// *retarget* the in-flight animation to the new lap distance, making the
/// incoming text race into place. Sampling one shared clock removes all three by
/// construction instead of guarding against them.
///
/// Width is measured with `NSAttributedString`, synchronously. The earlier
/// preference-based version had no way to prove the measurement had arrived, and
/// a zero width silently disables scrolling rather than failing visibly.
private struct MarqueeText: View {
    let text: String
    /// An NSFont rather than a SwiftUI Font, because measuring needs the real
    /// font metrics. The SwiftUI font is derived from it, so the string that's
    /// measured and the string that's drawn can't disagree.
    let nsFont: NSFont
    /// The visible width, passed in rather than measured. Measuring would be
    /// circular: this view's natural width is the whole string, so any container
    /// sized to fit its children sizes to that.
    let width: CGFloat
    /// When the current cycle's clock started. **Shared by every line**, which is
    /// what keeps them in exact lockstep rather than merely close.
    let anchor: Date
    /// Non-nil while motion is frozen — popover closed, or playback paused.
    /// Sampling this instant rather than the live date keeps the frozen frame
    /// stable even if the view re-renders for an unrelated reason, and the parent
    /// shifts `anchor` forward on resume so motion continues from where it
    /// stopped instead of restarting.
    let frozenAt: Date?
    /// Length of one shared cycle, computed by the parent from whichever line
    /// takes longest. Lines travel at the same speed, so a longer string
    /// genuinely takes longer and they finish at different moments — then each
    /// holds until this period is up, so every line restarts together instead of
    /// drifting into a permanent stagger.
    let cycleDuration: Double

    /// Points per second. Constant regardless of length: that's what makes a
    /// longer line take longer rather than scroll faster.
    static let speed: CGFloat = 27
    /// Blank space between the tail of one copy and the head of the next.
    static let gap: CGFloat = 28
    /// Rest at the start of every cycle, before scrolling begins again.
    static let pause: Double = 3
    /// How far each end fades to transparent, and equally how far in the text
    /// starts — so its first character is fully opaque rather than sitting
    /// half-dissolved in the leading gradient.
    ///
    /// Tied to the caller's horizontal bleed: the caller widens by this much per
    /// side, the text is inset by this much, and the net effect is that text
    /// begins level with every row's icon while the gradient occupies only the
    /// bleed.
    static let fade: CGFloat = Metrics.backgroundPadding

    static func measure(_ text: String, nsFont: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: nsFont]).width
    }

    /// Seconds to scroll one lap, or zero when the text fits and won't move.
    /// Used by the parent to find the longest line and size the shared cycle.
    static func scrollDuration(text: String, nsFont: NSFont, width: CGFloat) -> Double {
        let measured = measure(text, nsFont: nsFont)
        guard measured > width - fade else { return 0 }
        return Double((measured + gap) / speed)
    }

    /// Compared against the width remaining after the leading inset, since
    /// that's the space the text actually gets.
    private var overflows: Bool { Self.measure(text, nsFont: nsFont) > width - Self.fade }

    /// One full lap: the string plus the gap after it.
    private var lap: CGFloat { Self.measure(text, nsFont: nsFont) + Self.gap }

    var body: some View {
        if overflows {
            TimelineView(.animation(paused: frozenAt != nil)) { context in
                scrolling(at: frozenAt ?? context.date)
            }
        } else {
            // No fade when it fits: there's nothing to hide, and dimming the
            // ends of a short centred title would just look like a bug.
            label.frame(width: width, alignment: .center)
        }
    }

    private func scrolling(at now: Date) -> some View {
        HStack(spacing: Self.gap) {
            label
            label
        }
        // The +fade inset keeps the first character clear of the leading
        // gradient at rest. It shifts both copies equally, so the lap distance —
        // and the invisibility of the wrap — is unaffected.
        .offset(x: position(at: now.timeIntervalSince(anchor)) + Self.fade)
        .frame(width: width, alignment: .leading)
        .clipped()
        .mask(edgeFade)
    }

    /// Where this line sits within the shared cycle: held at the start for
    /// `pause`, then travelling at exactly `speed` until one lap is done, then
    /// held at the lap's end until the cycle comes round again.
    ///
    /// Holding at `-lap` is invisible, since the second copy there renders
    /// identically to the first copy at zero — which also means the wrap needs no
    /// special handling. The remainder does it.
    private func position(at elapsed: Double) -> CGFloat {
        guard cycleDuration > 0 else { return 0 }
        let phase = max(0, elapsed).truncatingRemainder(dividingBy: cycleDuration)
        guard phase > Self.pause else { return 0 }
        return -min(lap, CGFloat(phase - Self.pause) * Self.speed)
    }

    private var label: some View {
        Text(text)
            .font(Font(nsFont))
            .lineLimit(1)
            // Natural width, ignoring the proposed one — otherwise the Text
            // truncates itself and there's nothing to scroll.
            .fixedSize(horizontal: true, vertical: false)
    }

    /// Softens both ends so text dissolves rather than being cut off on a hard
    /// vertical edge.
    private var edgeFade: some View {
        let ratio = min(0.35, Self.fade / max(width, 1))
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: ratio),
                .init(color: .black, location: 1 - ratio),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// A full-width action row: just the word on the left, nothing on the right,
/// the whole line highlights on hover (macOS settings-menu style).
private extension View {
    /// A row of small glass badges floating just above this control, shown
    /// only while `hotkeys.hintsVisible` (toggled by "?", auto-hides after
    /// 3s — see `PopoverHotkeys`). Each control gets its own badge row rather
    /// than one big list, so the hint sits right on the thing it applies to;
    /// when a control has more than one bound key (e.g. previous track is
    /// J/⌥←/⌘←), each key gets its own separate box, laid out horizontally,
    /// rather than one merged string.
    ///
    /// `distance` is how far past the control's edge the badges float. Raising
    /// it needs matching room in the popover's padding — the badge draws
    /// outside the control's bounds, so past a point it collides with the
    /// popover's own chrome (its pointer arrow, at the top) and then clips at
    /// the window edge.
    ///
    /// Note this modifier can't fix z-order on its own: a `.zIndex` here only
    /// orders the badge against its *siblings inside the same container*. Rows
    /// that carry badges need `.zIndex(1)` where they sit in the body VStack,
    /// or a later `Divider()` sibling draws on top of them.
    @ViewBuilder
    func hotkeyHint(_ keys: [String], hotkeys: PopoverHotkeys, edge: Edge = .top, distance: CGFloat = Metrics.backgroundPadding) -> some View {
        overlay(alignment: edge == .top ? .top : .bottom) {
            if hotkeys.hintsVisible {
                HStack(spacing: LarcUI.smallFontSize / 2) {
                    ForEach(keys, id: \.self) { key in
                        Text(key)
                            .frame(minWidth: LarcUI.smallFontSize*1.5)
                            .font(LarcUI.hotkeyFont)
                            .fixedSize()
                            .padding(.horizontal, 3)
                            .padding(.vertical, 3)
                            // **Tint in front of the glass, not through it.**
                            // `.background` layers behind content, and the
                            // *first* one applied sits closest to it — so this
                            // yellow lands over the material below. Passing the
                            // tint to `glassEffect` instead was tried on the
                            // accessibility warning and renders a near-solid
                            // block: `Glass.tint(_:)` is not a low-opacity wash.
                            .background(
                                LarcUI.hintTint,
                                in: RoundedRectangle(cornerRadius: LarcUI.smallFontSize * 2 / 3)
                            )
                            .glassBackground(cornerRadius: LarcUI.smallFontSize * 2 / 3)
                    }
                }
                .shadow(radius: 1)
                .offset(y: edge == .top ? -distance : distance)
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hotkeys.hintsVisible)
    }

    func hotkeyHint(_ key: String, hotkeys: PopoverHotkeys, edge: Edge = .top, distance: CGFloat = Metrics.backgroundPadding) -> some View {
        hotkeyHint([key], hotkeys: hotkeys, edge: edge, distance: distance)
    }

}

/// Two filled triangles (built from "play.fill" — already a solid
/// right-pointing triangle, mirrored for prev — rather than a single
/// "forward.fill"/"backward.fill" glyph), touching (spacing ~= triangleSize),
/// that relay-animate on each press: the far one shrinks/fades out in place,
/// the near one shrinks-then-regrows while sliding into the far position,
/// and a new one grows/fades in at the near position.
///
/// Unlike a plain instant symbol swap, this only works at all because
/// `trigger` is a DeviceController trigger UUID
/// (previousTrackTrigger/nextTrackTrigger), bumped on every
/// previousTrack()/nextTrack() call regardless of whether it came from a
/// click or a hotkey — that's what makes hotkey presses visually confirmed.
///
/// Deliberately **one continuously-animated value per triangle** (`slots`),
/// with position/scale/opacity all *computed live* from that value, rather
/// than separately phase-scheduled sub-animations driven by
/// `DispatchQueue.main.asyncAfter` (an earlier version did that — a second
/// rapid press before the scheduled phase-2/rotation callbacks fired left
/// some triangles permanently stuck at an intermediate scale/opacity, since
/// the stale callbacks were skipped via a generation guard but nothing else
/// ever corrected the values they'd already set).
///
/// The raw `slots` values are **never reset or wrapped** — they just keep
/// incrementing by 1 forever, once per press, completely unbounded. A
/// second version of this same idea tried to keep them bounded with a
/// `DispatchQueue.main.asyncAfter`-scheduled wrap after each press, and that
/// had the exact same class of bug all over again: click faster than the
/// animation duration and every scheduled wrap gets cancelled by the next
/// press before it fires, so the raw values drift further and further
/// outside the visible range with nothing ever correcting them — eventually
/// every triangle is permanently past the window, i.e. gone. The fix isn't
/// "schedule the wrap more carefully", it's **not needing a wrap at all**:
/// `position`/`scale`/`opacity` normalize the (possibly huge) raw slot value
/// into the canonical period via `.truncatingRemainder(dividingBy: 3)`
/// before doing anything else, so rendering is correct for literally any
/// slot value, no matter how large — there is no failure mode left to hit,
/// regardless of click speed. Don't reintroduce a scheduled reset/wrap here.
private struct TrianglePairIcon: View {
    let flipped: Bool
    let trigger: UUID

    // Per-triangle continuous position, starting at the near/far/hidden
    // rest values. Normalized slot -1 = hidden (at the near x-position,
    // invisible); 0 = near (resting, visible); 1 = far (resting, visible);
    // 2 = fully exited (at the far x-position, invisible). The raw stored
    // value just keeps growing forever — see the type's doc comment.
    @State private var slots: [Double] = [0, 1, -1]

    private let spacing: CGFloat = 14.4     // 80% of the previous 18 — track controls sized to 80%
    private let triangleSize: CGFloat = 18
    private let duration: Double = 0.55

    var body: some View {
        // **Top-aligned.** A ZStack centres its children, so while its height
        // animates between two screens the incoming one is clipped at *both*
        // ends — and since the tint is a gradient, clipping the top moved which
        // part of the gradient landed there. That's the top and bottom colours
        // appearing to change on the way in. Anchored at the top, the gradient's
        // start is fixed and only the bottom is clipped, which is the end that
        // is arriving anyway.
        ZStack(alignment: .top) {
            ForEach(0..<3, id: \.self) { i in
                let slot = normalized(slots[i])
                Image(systemName: LarcIcon.play)
                    .font(.system(size: triangleSize))
                    .scaleEffect(x: (flipped ? -1 : 1) * scale(for: slot), y: scale(for: slot))
                    .offset(x: (flipped ? -1 : 1) * position(for: slot) * spacing)
                    .opacity(opacity(for: slot))
            }
        }
        // Recenters the visible pair in the frame. position(for:) clamps to
        // [0, 1], so at rest the two visible triangles sit at x-offsets 0 and
        // ±spacing — putting their centroid at ±spacing/2 rather than 0. The
        // glyphs were therefore drawn ~7pt off-centre inside their 45×45
        // hitbox, in opposite directions for prev vs next, which is what made
        // the hotkey badges (centred on the frame) look misaligned against
        // them.
        //
        // A static container offset: it shifts every triangle equally and
        // touches none of the slot math, so the animation is unaffected.
        .offset(x: (flipped ? 1 : -1) * spacing / 2)
        .onChange(of: trigger) { advance() }
    }

    /// Maps any real number onto the canonical [-1, 2) range — the pattern
    /// repeats every 3 slots, so this is safe to call on values that have
    /// grown arbitrarily large from many presses.
    private func normalized(_ slot: Double) -> Double {
        var s = slot.truncatingRemainder(dividingBy: 3)
        if s < -1 { s += 3 }
        if s >= 2 { s -= 3 }
        return s
    }

    /// Only moves during the near→far leg (slot 0...1) — pinned at the near
    /// x-position before that (hidden, growing in place) and at the far
    /// x-position after it (visible-then-exiting, shrinking in place).
    private func position(for slot: Double) -> Double {
        max(0, min(1, slot))
    }

    /// 1 at both rest positions (slot 0 and 1), dipping to 0.5 exactly at
    /// the midpoint of the near→far transit; ramps 0→1 growing in from
    /// hidden (slot -1...0) and 1→0 shrinking out once past far (slot 1...2).
    private func scale(for slot: Double) -> Double {
        if slot <= -1 { return 0 }
        if slot < 0 { return slot + 1 }
        if slot <= 1 { return 1 - 0.5 * sin(.pi * slot) }
        if slot < 2 { return 1 - (slot - 1) }
        return 0
    }

    private func opacity(for slot: Double) -> Double {
        if slot <= -1 || slot >= 2 { return 0 }
        if slot < 0 { return slot + 1 }
        if slot > 1 { return 2 - slot }
        return 1
    }

    private func advance() {
        withAnimation(.easeInOut(duration: duration)) {
            for i in slots.indices { slots[i] += 1 }
        }
    }
}


/// Carries a sub-screen's content height up to the popover, which needs it to
/// choose between hugging the content and scrolling it.
private struct SubScreenHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}



/// Internal, not fileprivate: the artwork tuning window previews the popover's
/// layers over this same material, and a second definition there would be a
/// second thing to keep in step.
extension View {
    /// Liquid Glass on macOS 26+, the pre-Tahoe material below it.
    ///
    /// A **runtime** availability check, not a compile-time `#if` — one
    /// universal binary still serves macOS 14 through 26 and the deployment
    /// target stays at 14.0. Everything else in this popover is a standard
    /// SwiftUI control, which adapts on its own: system-drawn controls pick
    /// their appearance from the OS at runtime given the app was linked
    /// against a new enough SDK (26.5 here). Only hand-styled surfaces like
    /// this one need the explicit branch.
    ///
    /// `.regular.tint(nil)` is just `.regular`, so the tintless call site
    /// needs no separate overload.
    ///
    /// Internal rather than fileprivate: the artwork tuning window previews its
    /// layers over the same material the popover uses, and a second definition
    /// there would be a second thing to keep in step.
    @ViewBuilder
    func glassBackground(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.tint(tint), in: RoundedRectangle(cornerRadius: cornerRadius))
        } else if let tint {
            background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
