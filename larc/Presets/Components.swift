import SwiftUI

/// The popover's shared visual language.
///
/// Everything the UI is built from lives here, and nothing re-implements a
/// look locally. That rule exists because it was already broken: `ActionRow`,
/// `ActionRowCompact` and `PresetRow` each grew their own hover fill with
/// different corner radii and insets, so the same gesture looked like three
/// different things on three screens.
///
/// There are only a handful of concepts in this app — a row you tap, a row with
/// a control, a tile in a grid, a wide option, a header. Adding a new look
/// should mean adding a case here, not styling in place.
enum LarcUI {
    /// **Three sizes, and that is the whole scale.** A title, a secondary line,
    /// and a screen's name.
    ///
    ///   - `rowFont` (12) — every title, whatever shape holds it: a row, a
    ///     setting row, a pill.
    ///   - `subtitleFont` (9) — everything subordinate to a title. A row's
    ///     second line, a pill's second line, the caption inside a tile, the
    ///     uppercase caption above a group, a numeric readout.
    ///   - `headerFont` (14) — a sub-screen's own name, which sits above the
    ///     content rather than in it.
    ///
    /// There were seven. `pillTitleFont` (10) made the same word smaller in a
    /// capsule than in a row; `pillSubtitleFont` and `tileCaptionFont` (both 8)
    /// were a second secondary size; `sectionLabelFont` and `valueFont` were
    /// `subtitleFont` with a weight and a digit setting attached, which is a
    /// modifier at the call site, not a size.
    ///
    /// **Vary weight and digit spacing freely; don't add a size.** A new number
    /// here has to justify itself against every existing one, and the previous
    /// four each looked reasonable alone and incoherent together.
    static let rowFont = Font.system(size: 12)
    static let smallFontSize: CGFloat = 9
    static let subtitleFont = Font.system(size: smallFontSize)
    static let hotkeyFont = Font.system(size: smallFontSize, weight: .medium, design: .monospaced)
    /// A sub-screen's title. Heavier and larger than a row, because it names the
    /// screen rather than sitting in it.
    static let headerFont = Font.system(size: 14, weight: .semibold)

    /// One hover fill for every tappable row, whatever screen it's on.
    static let hoverFill = Color.primary.opacity(0.08)
    static let restFill = Color.primary.opacity(0.06)

    /// A *control's* own surface — pill, tile, circle. Heavier than a row's,
    /// because a row's highlight appears on hover against nothing, while a
    /// control is a visible shape whether or not you're pointing at it.
    static let controlRestFill = Color.primary.opacity(0.08)
    static let controlHoverFill = Color.primary.opacity(0.14)
    /// What any disabled control dims to.
    static let disabledOpacity: Double = 0.4

    /// Wash over a hotkey badge's glass, so the badges read as a distinct layer
    /// rather than as more of the popover. Low enough to stay a tint: the glass
    /// underneath is what gives them their depth.
    static let hintTint = Color.yellow.opacity(0.35)

    /// A doubt about an option, not a refusal of it — see `LarcTile.caution`.
    /// Orange because it's the colour this popover already uses for "worth
    /// knowing, not an error"; red would overstate it and the accent is taken.
    static let cautionColor = Color.orange
    static let cautionDot: CGFloat = 5

    /// Something that stops you, as opposed to something worth knowing.
    ///
    /// **The difference is whether you can carry on.** Orange marks things that
    /// have already happened and can be ignored — a device refused an output, a
    /// tile is doubtful. Red is for a state you have to resolve before the UI
    /// will let you leave it, and a duplicate preset name is the only one today.
    /// Using orange for both would make neither mean anything.
    static let errorColor = Color.red

    /// A selected control: accent fill, white mark on top.
    ///
    /// The inverse of what it was. A white fill with an accent glyph reads as a
    /// *lit* control rather than a chosen one — and it depended on the 2pt
    /// accent ring to be legible at all, since white-on-near-white is barely a
    /// fill. With the ring gone (it duplicated what the fill already said) the
    /// weight has to move into the fill itself.
    ///
    /// Literal white rather than a semantic colour: this sits on the accent,
    /// not on the window, so it must not flip with the appearance. It's the
    /// same choice `NSButton`'s own selected state makes.
    static let selectedFill = Color.accentColor
    static let selectedForeground = Color.white

    // MARK: Glyph motion
    //
    // Two gestures, and they mean different things. A **bounce** is feedback:
    // the glyph drops and returns, once, because you pressed it. A **breath** is
    // state: the glyph swells and settles, indefinitely, because the control is
    // waiting on something. A control that starts waiting does both — bounce,
    // then breathe — which reads as "that press landed, now hold on".
    //
    // Both are SF Symbols' own effects; see `GlyphMotion`. Nothing about their
    // timing or depth is ours to set, which is the point — they match every
    // other symbol animation on the system.

    /// What a waiting control's own label fades to.
    ///
    /// Faded rather than hidden: "Scanning…" is still worth reading, and a
    /// capsule that empties out to a lone moving glyph looks broken rather than
    /// busy. The fade is what carries "not ready yet"; the breath is what
    /// carries "still working".
    static let waitingLabelOpacity: Double = 0.4

    /// Icon sizes, **optical** — cap height, the same measure text uses. See
    /// `LarcGlyph` for why not widths.
    ///
    /// `iconSingle` goes beside a single line of text: a row, a setting row, a
    /// chevron or checkmark, the mute button. `iconDouble` goes with two lines
    /// beside it or a label beneath it — a row with a subtitle, a pill, a tile,
    /// a circle toggle, a screen header.
    ///
    /// **Both are 14 at the moment**, on trial: if one size reads correctly in
    /// every context then there is no second size, and the pair collapses to
    /// one. They stay separate until that's confirmed on screen, because
    /// merging them is a rename and splitting them again is not.
    static let iconSingle: CGFloat = 14
    static let iconDouble: CGFloat = 14

    /// The layout box every icon is centred in, whichever size it is.
    ///
    /// This is what makes a column of icons line up: an SF Symbol's width
    /// depends on the glyph, so alignment has to come from the box rather than
    /// from the mark inside it. Wider than any glyph needs, so a broad one like
    /// `hifispeaker.2` has somewhere to sit without crowding the text.
    ///
    /// Stated directly rather than derived from the icon size. It was
    /// `iconDouble + slack` for a while, which made the column move whenever an
    /// icon size was tuned — the opposite of what a column is for. 24 is also
    /// half the 48pt pill unit, so an icon column and a control divide the grid
    /// the same way.
    static let iconColumn: CGFloat = 24
    /// Width of a settings row's trailing control when what it shows is
    /// open-ended.
    ///
    /// `.fixedSize()` is right for a control whose values are known and short —
    /// Volume Step shows one or two digits. It is wrong for one showing a name
    /// the user chose: a room-correction profile called "summer fan on (Stereo)"
    /// grew the picker until the row's `Spacer` collapsed and the title beside
    /// it truncated to nothing, leaving an icon and a dropdown and no indication
    /// of what they set. (That title is "RC" now, so it has room to spare — but
    /// the cap is about the profile name being unbounded, not the title being
    /// long, so shortening one didn't fix the other.)
    ///
    /// **A ceiling, not a width.** The control sizes to whatever it's showing
    /// via `popUpWidth(for:)` and only stops here — so "None" takes 81pt rather
    /// than sitting in a 155pt box with 74pt of empty bezel beside it, which is
    /// what a fixed width did.
    ///
    /// Three quarters of the content width less 2. Past this the row reads as a
    /// dropdown with a label rather than a setting with a control.
    ///
    /// When a name does hit the ceiling it truncates rather than the title,
    /// which is the right way round — the title is fixed and knowable, the
    /// profile name is not.
    ///
    /// Measured at the system control size, with the 49pt of popup chrome that
    /// `popUpWidth(for:)` adds: "None" comes to 81 and "Auto (Stereo)" to 131,
    /// so both sit at their own width well inside the 155.5 ceiling. "desktop
    /// edifiers (L/R)" wants 180 and "summer fan on (Stereo)" 193, so those two
    /// cap and truncate.
    ///
    /// It was a fixed 30% when the title read "Room Correction" and needed most
    /// of the row, then a fixed 75%, then half. Fixed was the wrong shape for
    /// it throughout: a picker showing "None" has nothing to do with 155pt.
    static var settingControlMaxWidth: CGFloat {
        Metrics.contentWidth * 0.75 - 8
    }

    /// Width a `.menu` Picker needs to show exactly this title and no more.
    ///
    /// **`.fixedSize()` cannot do this, and that's why it never looked like it
    /// worked.** It hugs the intrinsic width, and `NSPopUpButton`'s intrinsic
    /// width is that of its *widest menu item*, not its selected one — measured
    /// at 189pt whichever of two devices was chosen, against 145 for the shorter
    /// name on its own. One long device name therefore makes the picker
    /// permanently as wide as that name, which against a 210pt content width is
    /// indistinguishable from full width. No frame modifier fixes a wrong
    /// intrinsic size; the width has to be stated.
    ///
    /// Chrome — arrow, insets, bezel — measured 48.2 to 48.6 across titles from
    /// one character to thirty-four, so it's a constant to add rather than a
    /// proportion to scale. 49 rounds up, because a point short truncates.
    static func popUpWidth(for title: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let text = (title as NSString).size(withAttributes: [.font: font]).width
        return ceil(text) + popUpChrome
    }
    static let popUpChrome: CGFloat = 49

    /// Between one group of controls and the next, where nothing labels them.
    ///
    /// The Controls screen and the preset editor used to caption every group —
    /// INPUT, OUTPUT, CHANNELS. The captions said what the glyphs already do,
    /// and in the editor each carried a "· not set" that nobody wanted. Space
    /// separates the groups instead, which is why this has to be clearly larger
    /// than the 6pt between tiles inside one: three times it, so the grouping
    /// reads without a rule or a word.
    static var sectionGap: CGFloat { gridSpacing * 3 }

    /// Between a row's icon and its text.
    static let rowSpacing: CGFloat = 4
    static let rowVerticalPadding: CGFloat = 5
    /// Between rows in a list. **The same value the main screen uses**, not a
    /// similar one: packing sub-screen rows tighter made their hover fills
    /// nearly touch, so the identical highlight read as a solid block there and
    /// as a discrete highlight on the main screen.
    static var listSpacing: CGFloat { Metrics.rowSpacing }
}

/// An SF Symbol at a shared optical size, centred in a shared layout box.
///
/// **Size is a font size, not a width.** SF Symbols are font glyphs, so
/// `.font(.system(size: 14))` matches them to a 14pt cap height — a chevron and
/// a speaker then read as the same weight of mark, exactly as "i" and "W" are
/// the same size at different widths.
///
/// Sizing by width was tried and is wrong in a way that's worth recording: a
/// chevron is about 1:2, so forcing it to 14 wide rendered it ~28 tall, towering
/// over 12pt text, while `hifispeaker.2` at 2:1 shrank to ~7 tall and vanished.
/// It also discarded font weight, because a resizable image no longer takes one.
///
/// Alignment comes from the **box**, not the glyph: every icon is centred in the
/// same width, so a column of them lines up however wide each glyph happens to
/// be. The box is a frame, not a clip — a very wide glyph overhangs slightly
/// into the 6pt grid gap rather than being cut off.
struct LarcGlyph: View {
    let symbol: String
    /// Optical size — cap height, matching text of the same size.
    var size: CGFloat = LarcUI.iconSingle
    /// Layout width. Defaults to the shared column so icons align by default.
    var box: CGFloat? = nil
    var weight: Font.Weight = .regular

    /// Motion comes from the enclosing control through the environment, not as
    /// an argument.
    ///
    /// Every control that holds a glyph also owns the press counter driving it,
    /// so passing it down meant four components threading the same two values
    /// through their content — and a glyph nested any deeper (a preset row's
    /// tile, say) simply couldn't reach it. A glyph outside any control reads
    /// the defaults and stays still, which is right.
    @Environment(\.glyphBounce) private var bounce
    @Environment(\.glyphBreathing) private var breathing

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: weight))
            .glyphMotion(bounceUp: bounce.up, bounceDown: bounce.down,
                         breathing: breathing)
            .frame(width: box ?? LarcUI.iconColumn)
    }
}

/// Forces the enclosing `NSScrollView` to overlay scrollers.
///
/// **The only way to stop a scroller taking horizontal space.** With "Show
/// scroll bars: Always" AppKit uses *legacy* scrollers, laid out beside the
/// content rather than floating over it, so the usable width shrinks by ~15pt
/// the moment a screen becomes scrollable — and every row shifts sideways.
/// `.scrollIndicators` cannot change that; it only chooses whether indicators
/// show. `NSScrollView.scrollerStyle` can, and SwiftUI doesn't expose it.
///
/// A zero-size probe in a `.background`, **not** a wrapped control — the ban on
/// representables in this popover is about hosting controls, which twice blanked
/// the whole window. This adds no view of its own and reads no geometry.
///
/// Fails silently if the hierarchy ever changes shape: no scroll view found
/// means no change, which is exactly today's behaviour.
private struct GlyphBounceKey: EnvironmentKey {
    static let defaultValue = BounceState()
}

private struct GlyphBreathingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var glyphBounce: BounceState {
        get { self[GlyphBounceKey.self] }
        set { self[GlyphBounceKey.self] = newValue }
    }
    var glyphBreathing: Bool {
        get { self[GlyphBreathingKey.self] }
        set { self[GlyphBreathingKey.self] = newValue }
    }
}

/// Drops keyboard focus, so a *click* doesn't leave a ring behind.
///
/// **`.focusable()` makes a view focusable by every route, including the mouse.**
/// A native macOS button isn't: clicking one runs it and leaves focus alone, and
/// only Tab moves the ring. Making our controls focusable to fix Tab therefore
/// gave every click a persistent ring — the exact thing this popover has spent
/// six rounds trying not to draw.
///
/// So focus is resigned on tap and kept on a key press. The rule stays what
/// CLAUDE.md settled on: **no rings until you ask**, and a click is not asking.
@MainActor
func larcClearKeyboardFocus() {
    NSApp.keyWindow?.makeFirstResponder(nil)
}

/// The bounce-and-breathe motion described in `LarcUI`'s glyph-motion notes,
/// using SF Symbols' own effects rather than anything hand-animated.
///
/// **`.symbolEffect` is the right tool and the only one worth using here.** It
/// animates the symbol's own layers, so a multi-layer glyph moves as the
/// designer intended instead of the whole image being shoved around by a
/// transform; it needs no state, no clock and no cancellation; and it can't
/// leave a glyph stuck part-way, which is the failure mode two hand-built
/// animations in this project have already hit.
///
/// The one wrinkle is the deployment target. `.bounce` has been there since
/// macOS 14, but `.breathe` arrived in 15, so the older system falls back to
/// `.pulse` — also built in, also indefinite, and the closest thing to a breath
/// available there.
struct GlyphMotion: ViewModifier {
    /// Presses that bounce upward — every ordinary press, and switching a
    /// toggle on.
    var bounceUp: Int
    /// Presses that bounce downward — switching a toggle off. The direction
    /// carries the meaning: up is something starting, down is it stopping.
    var bounceDown: Int
    var breathing: Bool

    func body(content: Content) -> some View {
        // **Both directions are always attached**, each watching its own
        // counter, rather than one effect whose direction is chosen per press.
        // Swapping which modifier is applied would change the view's identity
        // mid-animation; and deriving two counters from one shared number makes
        // the *other* direction's counter change too, firing both bounces at
        // once. Two independent counters, each only ever incrementing, is the
        // version with no cross-talk.
        breathe(
            content
                .symbolEffect(.bounce.up, value: bounceUp)
                .symbolEffect(.bounce.down, value: bounceDown)
        )
    }

    @ViewBuilder
    private func breathe(_ content: some View) -> some View {
        if #available(macOS 15.0, *) {
            content.symbolEffect(.breathe.plain, options: .repeat(.continuous),
                                 isActive: breathing)
        } else {
            content.symbolEffect(.pulse, options: .repeating,
                                 isActive: breathing)
        }
    }
}

extension View {
    func glyphMotion(bounceUp: Int, bounceDown: Int, breathing: Bool) -> some View {
        modifier(GlyphMotion(bounceUp: bounceUp, bounceDown: bounceDown,
                             breathing: breathing))
    }
}

/// A control's press counters, kept together so every control tracks them the
/// same way.
///
/// Most controls only ever bounce up. A toggle is the exception: it bounces
/// down when it's switching *off*, so the gesture reads as the state going
/// away rather than as one more press.
struct BounceState: Equatable {
    private(set) var up = 0
    private(set) var down = 0

    /// `activating: false` is what makes a toggle bounce downward on its way
    /// off. Everything that isn't a toggle leaves it true.
    mutating func press(activating: Bool = true) {
        if activating { up += 1 } else { down += 1 }
    }
}

/// Everything a pill, a tile and a circle do identically — which turned out to
/// be everything except their shape and what's inside them.
///
/// **This is what makes "a circle is just a 1×1 pill" true rather than a
/// comment.** The three were separate structs agreeing only by convention, each
/// with its own copy of the hover fill, the selected colours, the disabled
/// opacity, the press counter and the hover tracking. Five chances to drift, and
/// they already had: `LarcTile` took `isEnabled: Bool = true` where the other two
/// took `disabled: Bool = false`, the same flag inverted.
///
/// A control now supplies a shape and its contents. Nothing else.
struct LarcControl<S: Shape, Content: View>: View {
    let shape: S
    var selected = false
    var disabled = false
    /// Waiting on something: its glyph breathes. See `GlyphMotion`.
    var isWaiting = false
    /// Off for a control whose press starts it waiting, where the breath is
    /// already the acknowledgement — Controls and Scan.
    var bounces = true
    /// A toggle bounces *down* when the press is switching it off. Anything
    /// that isn't a toggle always bounces up, because there's no "off" to go to.
    var isToggle = false
    let action: () -> Void
    @ViewBuilder let content: Content

    @State private var hovering = false
    @State private var bounce = BounceState()

    var body: some View {
        // **A focusable view, not a Button.**
        //
        // A `.plain` Button is left out of SwiftUI's key view loop, so Tab could
        // not reach any of these — the redesign replaced this popover's Toggles
        // and Pickers with pills and circles, taking the main screen from nine
        // focusable stops to two. Wrapping the Button in `.focusable()` fixed
        // reachability and introduced a worse bug: two focus targets per
        // control, so every pill and row took two Tab presses in either
        // direction.
        //
        // One focusable view with its own key handling is exactly one stop. The
        // Button bought nothing else here — the fill, the press bounce and the
        // hover are all ours already, and the accessibility traits it provided
        // are restated below.
        content
            .foregroundStyle(selected ? LarcUI.selectedForeground : .primary)
            .background { shape.fill(fill) }
            .contentShape(shape)
            // Keyed to the resolved colour rather than to `selected` and
            // `hovering` separately: `fill` already encodes both, so one
            // modifier covers pointing at a control, selecting it, and leaving
            // it — and the foreground crosses with it instead of snapping to
            // white a frame early.
            //
            // Stock in both senses: `.animation(_:value:)` rather than a timer,
            // and `.default` rather than a duration chosen by eye.
            .animation(.default, value: fill)
            .opacity(disabled ? LarcUI.disabledOpacity : 1)
            // Blocks the tap and the key handlers as well as focus, so `press()`
            // never has to be the only thing standing between a disabled control
            // and its action.
            .disabled(disabled)
            .focusable(!disabled)
            .onHover { hovering = $0 }
            // Focus is resigned here, not in `press()`: a key press should keep
            // the ring, a click should never have taken it.
            .onTapGesture { press(); larcClearKeyboardFocus() }
            // Space and Return, the two keys a button answers to. Returning
            // `.handled` stops them reaching PopoverHotkeys, which is what keeps
            // Space free to open the device picker when *that* has focus.
            .onKeyPress(.space) { press(); return .handled }
            .onKeyPress(.return) { press(); return .handled }
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction { press() }
            // Handed down rather than passed in, so a glyph at any depth inside
            // the content picks it up. See LarcGlyph.
            .environment(\.glyphBounce, bounce)
            .environment(\.glyphBreathing, isWaiting)
    }

    private func press() {
        guard !disabled else { return }
        if bounces { bounce.press(activating: isToggle ? !selected : true) }
        action()
    }

    /// Hover is ignored while disabled: a control that can't be pressed
    /// shouldn't light up under the pointer as though it could.
    private var fill: Color {
        if selected { return LarcUI.selectedFill }
        return hovering && !disabled ? LarcUI.controlHoverFill : LarcUI.controlRestFill
    }
}

/// The hover/selection background shared by every row-shaped control.
///
/// A modifier rather than a wrapper view so it can be applied to rows whose
/// content differs, while keeping the corner radius and the bleed identical.
/// The bleed is what lets the fill breathe past the row's content without
/// shifting the icons, which are aligned to the content gutter.
struct RowHighlight: ViewModifier {
    var hovering: Bool
    var selected: Bool = false

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: Metrics.highlightCornerRadius)
                .fill(fill)
                .padding(.horizontal, -Metrics.backgroundPadding)
                .padding(.vertical, -Metrics.highlightVerticalBleed)
                // Inside the background, so only the shape animates. Applied to
                // `content` it would also catch the row's own text — and a row
                // whose title changes while you're pointing at it would
                // cross-fade the words as well as the fill.
                .animation(.default, value: fill)
        }
    }

    private var fill: Color {
        if selected { return Color.accentColor.opacity(0.12) }
        return hovering ? LarcUI.hoverFill : .clear
    }
}

extension View {
    func rowHighlight(hovering: Bool, selected: Bool = false) -> some View {
        modifier(RowHighlight(hovering: hovering, selected: selected))
    }
}

/// A tappable row: icon, title, optional subtitle, optional trailing text.
///
/// The single row primitive. `ActionRow` on the main screen and the rows inside
/// sub-screens are the same control at two type sizes, not two controls.
struct LarcRow: View {
    let title: String
    let systemImage: String
    var subtitle: String? = nil
    /// Right-aligned text — a hotkey hint, a value, a count.
    var trailing: String? = nil
    /// Shown when the row leads somewhere.
    var showsChevron = false
    /// Shown when the row *is* a choice and this is the chosen one.
    var showsCheckmark = false
    var destructive = false
    var disabled = false
    var selected = false
    /// Replaces the icon entirely, for rows fronted by a preset's own tile.
    var leading: AnyView? = nil
    var isWaiting = false
    let action: () -> Void

    @State private var hovering = false
    @State private var bounce = BounceState()

    var body: some View {
        // A focusable view rather than a Button, same as LarcControl and for the
        // same reason: `.focusable()` around a plain Button gives two Tab stops.
        Group {
            HStack(spacing: LarcUI.rowSpacing) {
                // Icon in its own fixed column rather than inside a Label: a
                // Label puts the icon at the VStack's leading edge, which drags
                // the subtitle underneath it instead of under the title.
                // Both branches get the same column. The leading view used to
                // be passed through unframed, so a preset row's tile sat at its
                // own width and dragged the title left of every other row's —
                // the icon column existing but only half the rows using it.
                Group {
                    if let leading {
                        leading
                    } else {
                        LarcGlyph(
                            symbol: systemImage,
                            size: subtitle == nil ? LarcUI.iconSingle : LarcUI.iconDouble
                        )
                    }
                }
                .frame(width: LarcUI.iconColumn)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(LarcUI.subtitleFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let trailing {
                    Text(trailing)
                        .font(LarcUI.subtitleFont)
                        .foregroundStyle(.secondary)
                }
                if showsCheckmark {
                    LarcGlyph(symbol: LarcIcon.selected, size: LarcUI.iconSingle)
                }
                if showsChevron {
                    LarcGlyph(symbol: LarcIcon.disclosure, size: LarcUI.iconSingle)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .focusable(!disabled)
        .onTapGesture { press(); larcClearKeyboardFocus() }
        .onKeyPress(.space) { press(); return .handled }
        .onKeyPress(.return) { press(); return .handled }
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction { press() }
        .font(LarcUI.rowFont)
        .padding(.vertical, LarcUI.rowVerticalPadding)
        .rowHighlight(hovering: hovering && !disabled, selected: selected)
        .foregroundStyle(foreground)
        .disabled(disabled)
        .onHover { hovering = $0 }
        // A row keeps its own button rather than using LarcControl: its
        // highlight *bleeds* past its content by `backgroundPadding`, which is
        // the one thing a control surface deliberately doesn't do. It publishes
        // the same motion, so its glyph behaves identically.
        .environment(\.glyphBounce, bounce)
        .environment(\.glyphBreathing, isWaiting)
    }

    private func press() {
        guard !disabled else { return }
        bounce.press()
        action()
    }

    private var foreground: Color {
        if disabled { return .secondary }
        if destructive { return .red }
        if selected { return .accentColor }
        return .primary
    }
}

/// A row that carries a control: term and icon on the left, control on the
/// right.
///
/// This is the popover's settings idiom — Media Keys, Volume Step, Launch at
/// Login all read this way — and it was previously written out by hand at each
/// site, which is how a leading toggle crept into the preset editor and looked
/// foreign. A control belongs on the trailing edge here; if it needs to be
/// somewhere else, it isn't this component.
struct LarcSettingRow<Control: View>: View {
    let title: String
    let systemImage: String
    var disabled = false
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: LarcUI.rowSpacing) {
            LarcGlyph(symbol: systemImage, size: LarcUI.iconSingle)
            // **The title never truncates.** It's fixed and knowable; the
            // control's contents are not, so the control is the thing that
            // should give. Without this, "RC" — sixteen points of text — came
            // out as "…" because the picker's frame is fixed and SwiftUI
            // squeezed the only flexible thing left.
            Text(title).lineLimit(1).fixedSize()
            Spacer(minLength: 4)
            control
        }
        .font(LarcUI.rowFont)
        .foregroundStyle(disabled ? .secondary : .primary)
    }
}

/// A tile in a grid: glyph above a caption, inside a rounded square.
///
/// Used wherever a small fixed set is mutually exclusive — inputs, outputs,
/// channel modes. Selection follows Control Center: filled, accent foreground,
/// and a ring, so it never depends on colour alone.
struct LarcTile: View {
    let symbol: String
    /// Optional: a row of four unlabelled shapes reads faster than four
    /// captioned ones, where the glyph already says what it is.
    var label: String?
    var isActive = false
    /// **`disabled`, not `isEnabled`.** It was the inverted one of the three,
    /// which is the sort of difference that gets a flag passed the wrong way
    /// round exactly once.
    var disabled = false
    /// Standing in for a value that hasn't arrived: breathes, and shows no
    /// label because there isn't one to show yet.
    var isWaiting = false
    /// Something is known to be doubtful about this option, without it being
    /// unavailable. Draws a caution dot; still fully selectable.
    ///
    /// Deliberately not `disabled`. A greyed-out control says "not for you",
    /// which is a claim we can't back — the only evidence is one readback that
    /// didn't confirm, and that has been wrong. This says "this didn't work
    /// last time" and leaves the decision where it belongs.
    var caution = false
    /// Tooltip, and what a screen reader is told. Worth having whenever
    /// `caution` is set, since a dot alone doesn't say why.
    var cautionNote: String? = nil
    let action: () -> Void

    var body: some View {
        LarcControl(
            shape: RoundedRectangle(cornerRadius: LarcUI.tileRadius, style: .continuous),
            selected: isActive, disabled: disabled, isWaiting: isWaiting,
            action: action
        ) {
            VStack(spacing: 2) {
                LarcGlyph(symbol: symbol, size: LarcUI.iconDouble)
                    .frame(height: 20)
                // Inside the tile rather than under it, so a long label can't
                // change the grid's row height.
                if let label {
                    Text(label)
                        .font(LarcUI.subtitleFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: LarcUI.tileHeight)
            // Overlaid rather than placed in the stack, so a tile with a caution
            // is exactly as tall as one without and the grid stays even.
            .overlay(alignment: .topTrailing) {
                if caution {
                    Circle()
                        .fill(LarcUI.cautionColor)
                        .frame(width: LarcUI.cautionDot, height: LarcUI.cautionDot)
                        // Ringed in the tile's own fill so it separates from a
                        // selected tile's accent as clearly as from a grey one —
                        // orange on blue is legible but muddy where they touch.
                        .padding(2)
                        .background(Circle().fill(.background))
                        .padding(5)
                }
            }
        }
        .help(caution ? (cautionNote ?? "") : "")
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let name = label ?? symbol
        guard caution, let cautionNote else { return name }
        return "\(name). \(cautionNote)"
    }
}

extension LarcUI {
    /// Tiles stretch to fill their grid column; only the height is fixed, so
    /// three columns always span the content width exactly.
    /// **Every control is a pill. A circle is just a 1×1 one.**
    ///
    /// Widths come in units, and a wider pill spans whole units *plus the gaps
    /// it swallows* — so a double pill lands exactly where two singles and their
    /// gap would, and anything below it lines up without arithmetic at the call
    /// site.
    ///
    /// The unit is derived from the content width rather than chosen, so four
    /// singles across fill the row exactly. Picking a round 48 instead left 2pt
    /// unaccounted for, which is the kind of slack that turns into a
    /// "why doesn't this line up" an hour later. 48.5 renders cleanly: half a
    /// point is one pixel on a retina display.
    static var pillSingle: CGFloat { (Metrics.contentWidth - gridSpacing * 3) / 4 }
    static var pillDouble: CGFloat { pillSingle * 2 + gridSpacing }
    static var pillQuad: CGFloat { Metrics.contentWidth }

    /// Square by definition — a single pill is a circle, so its height is its
    /// own width. Every taller-or-wider control shares it, which is what puts a
    /// row of mixed pills and circles on one baseline.
    static var pillHeight: CGFloat { pillSingle }

    /// Tiles are pill-height too, so a grid of tiles and a row of pills agree.
    static var tileHeight: CGFloat { pillHeight }

    /// The tinted square that stands in for a preset, at the two sizes it
    /// appears: half a pill wherever it sits in a row, and a whole pill in the
    /// icon picker's preview.
    ///
    /// Half a pill is also exactly `iconColumn`, so a preset row's tile fills
    /// the same column as every other row's glyph and their titles line up.
    /// That's why it's derived rather than picked: the two have to agree, and
    /// they were 22 against 24 when they were chosen separately.
    /// 20, not the 24 it was. A preset's tile sits in the `iconColumn` (24)
    /// beside a title, and filling that column entirely made it the heaviest
    /// mark on a list of rows whose other icons are 14pt glyphs. Smaller than
    /// its column, so it reads as an icon rather than as a block.
    static let presetTile: CGFloat = 20
    static var presetTileLarge: CGFloat { pillHeight }
    /// Where a pill's glyph box starts, measured from the capsule's edge.
    ///
    /// **Derived from the capsule's own radius**, which is half its height. A
    /// capsule's leftmost point is at the vertical midline, exactly where a
    /// centred icon sits — so the curve intrudes far less than it looks like it
    /// should, and a large inset only pushes the glyph toward the middle where
    /// it stops reading as a leading icon. A quarter of the height clears the
    /// corner visually while keeping the glyph on the left, and follows
    /// `pillHeight` if that ever changes.
    static var pillLeadingInset: CGFloat { pillHeight / 4 }

    /// Superseded by `pillDouble`, which is the same measurement named for what
    /// it is: two units wide. Kept as an alias while call sites migrate.
    static var halfWidth: CGFloat { pillDouble }
    static let tileRadius: CGFloat = 12
    /// Four across, so a tile is exactly `pillSingle` (48) and a grid of tiles
    /// lines up with a row of circles. At three the tile was 66 — a width
    /// nothing else in the layout shared, which is why an input grid and a
    /// channel row never sat on the same columns.
    ///
    /// The cost is 22pt of label width, which is what forced "HDMI ARC",
    /// "Headphones" and "Bluetooth" to shorten. See `AudioInput.displayName`.
    static let tileColumns = 4
    /// Between tiles, pills and circles alike.
    ///
    /// Also what sets the pill unit, so gap and height are one decision rather
    /// than two: at 6 against a 210pt content width the four-across grid works
    /// out to exactly 48, and three tiles to exactly 66.
    ///
    /// The pair was chosen together for that. Most combinations leave the unit
    /// fractional, or leave its half and quarter fractional — and those two are
    /// a capsule's radius and a pill's leading inset, so they show up on screen.
    /// `Metrics.contentMargin` is 15 for the same reason.
    static let gridSpacing: CGFloat = 6
}

/// A capsule button: glyph and label side by side, fully rounded ends.
///
/// For destinations that deserve more weight than a list row — the two that
/// lead out of the main screen, and Scan Network. Sized by its container, so a
/// row of them divides the width rather than each choosing its own.
struct LarcPill: View {
    let title: String
    let systemImage: String
    var subtitle: String? = nil
    var isActive = false
    var disabled = false
    /// Waiting on something: the label fades and the glyph breathes. Distinct
    /// from `disabled`, which says "you can't", where this says "not yet".
    var isWaiting = false
    /// Off for a pill whose press starts it waiting — Controls and Scan.
    ///
    /// For those two the breath *is* the acknowledgement, and it begins the
    /// instant the press lands. A bounce first only delays it, and reads as two
    /// separate responses to one press rather than one continuous one.
    var bouncesOnPress = true
    let action: () -> Void

    var body: some View {
        LarcControl(shape: Capsule(), selected: isActive, disabled: disabled,
                    isWaiting: isWaiting, bounces: bouncesOnPress,
                    action: action) {
            HStack(spacing: LarcUI.rowSpacing) {
                LarcGlyph(symbol: systemImage, size: LarcUI.iconDouble)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(LarcUI.subtitleFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                // Only the words fade. The glyph is the thing still moving, so
                // dimming it too would mute the one part that's saying anything.
                .opacity(isWaiting ? LarcUI.waitingLabelOpacity : 1)
                .animation(.easeInOut(duration: 0.2), value: isWaiting)
                Spacer(minLength: 0)
            }
            .font(LarcUI.rowFont)
            // Leading, not centred: a row of pills with centred contents has
            // its glyphs landing at different x positions depending on how long
            // each label is, which reads as misalignment rather than as
            // centring. Inset by the capsule's own curve so the glyph clears it.
            .padding(.leading, LarcUI.pillLeadingInset)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: LarcUI.pillHeight)
        }
    }
}

/// A circular on/off button — literally a one-unit pill, since `pillHeight` is
/// `pillSingle` and a shape that wide and that tall is a circle.
///
/// Control Center's shape for a thing that is simply on or off, as opposed to
/// one of several. Selected reads exactly as a tile's does — accent fill, white
/// glyph — so the two are one family differing only in outline.
///
/// **The one control that is a toggle**, which is why it passes `isToggle`: a
/// press while on is a press that switches off, so its glyph drops rather than
/// lifting, and the gesture is readable without watching the fill.
struct LarcCircleToggle: View {
    let symbol: String
    let label: String
    var isOn = false
    var disabled = false
    var isWaiting = false
    let action: () -> Void

    var body: some View {
        LarcControl(shape: Circle(), selected: isOn, disabled: disabled,
                    isWaiting: isWaiting, isToggle: true, action: action) {
            // No caption. A label under the circle has to be tiny to fit, and at
            // that size it truncated to "Media…" — which communicates less than
            // the glyph already does. The name lives in the tooltip and in the
            // accessibility label instead.
            LarcGlyph(symbol: symbol, size: LarcUI.iconDouble)
                .frame(width: LarcUI.pillHeight, height: LarcUI.pillHeight)
        }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A sub-screen's title bar: back control, icon, title.
///
/// The back control is always present rather than appearing conditionally — a
/// control that comes and goes makes the header jump, and every sub-screen has
/// a parent by construction.
struct LarcScreenHeader: View {
    let symbol: String
    let title: String
    var tint: Color = .secondary
    let onBack: () -> Void

    @State private var hovering = false
    /// Read here rather than passed in, so every header honours it without each
    /// caller remembering to.
    @ObservedObject private var navigation = PopoverNavigation.shared

    var body: some View {
        HStack(spacing: LarcUI.rowSpacing) {
            Button(action: onBack) {
                // Square, at the height the header claims — Metrics.headerHeight
                // is derived from this, and subScreenMaxHeight subtracts it.
                LarcGlyph(symbol: LarcIcon.back, size: LarcUI.iconSingle)
                    .frame(width: Metrics.headerHeight, height: Metrics.headerHeight)
                    .background {
                        Circle().fill(hovering && !navigation.popBlocked
                                      ? LarcUI.hoverFill : .clear)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(navigation.popBlocked)
            .opacity(navigation.popBlocked ? LarcUI.disabledOpacity : 1)
            .onHover { hovering = $0 }

            LarcGlyph(symbol: symbol, size: LarcUI.iconDouble)
                .foregroundStyle(tint)
                .frame(width: 18)

            Text(title)
                .font(LarcUI.headerFont)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
    }
}

/// A small uppercase caption above a group.
struct LarcSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(LarcUI.subtitleFont.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A labelled group: caption, then content.
///
/// `note` is right-aligned in the caption row and is how a group says it isn't
/// doing anything — "Not set" beside INPUT reads better than an extra tile in
/// the grid meaning the same thing.
struct LarcSection<Content: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                LarcSectionLabel(text: title)
                if let note {
                    Text(note)
                        .font(LarcUI.subtitleFont.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            content
        }
    }
}

/// The tinted rounded square standing in for a preset wherever it appears — its
/// row, its editor's header, the icon picker's preview.
struct LarcPresetIcon: View {
    let symbol: String
    let tint: PresetTint
    /// Defaults to the in-row size, which equals the icon column — so a preset
    /// row needs no size at the call site and still aligns with every other row.
    var size: CGFloat = LarcUI.presetTile

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tint.color)
            .frame(width: size, height: size)
            .overlay {
                // Sized as a fraction of the tile rather than from the shared
                // scale, because this glyph has to stay proportional to a square
                // that appears at several sizes — 20 in a row, 26 in an editor,
                // 48 in the picker's preview.
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.white)
            }
    }
}
