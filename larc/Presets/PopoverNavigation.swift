import SwiftUI

/// Which screen the popover is showing, and everything the UI needs to say
/// about it.
///
/// **A screen is defined once, here, and every other mention derives from it.**
/// The pill that navigates to a screen reads its title and symbol from the
/// screen; a screen that acts on another names itself from that other one, so
/// "Configure Presets" is literally `configure` applied to `Self.presets.title`
/// rather than a second string that happens to match.
///
/// This replaced a separate table of names. That was worse than the problem it
/// fixed: renaming Configure to Controls updated the table while the enum case
/// stayed `.configure`, so one concept still had two names and the old one kept
/// surfacing. If a name needs changing, it should be changeable in exactly one
/// place — and that place is the case itself.
enum PopoverScreen: Equatable, Hashable {
    case controls
    case presets
    case configurePresets
    case editPreset(UUID)
    case iconPicker(UUID)
    case about
    case queue
    #if LARC_DEV
    /// Component and icon gallery. Only exists in a `--dev` build.
    case dev
    #endif

    /// The screen's own name. Derived names are built from these, never
    /// duplicated.
    var title: String {
        switch self {
        case .controls: return "Controls"
        case .presets: return "Presets"
        case .configurePresets: return "Configure \(Self.presets.title)"
        case .editPreset: return Self.presetNoun
        case .iconPicker: return "Icon"
        case .about: return "About"
        case .queue: return "Queue"
        #if LARC_DEV
        case .dev: return "Dev"
        #endif
        }
    }

    /// Singular of `presets`, for talking about one of them. The only piece
    /// that can't be derived, since English plurals aren't mechanical.
    static let presetNoun = "Preset"

    /// Outline weights throughout — the popover's icons are all outlines, and a
    /// filled glyph among them reads as heavier rather than as different.
    var symbol: String {
        switch self {
        // Everything about presets shows the presets glyph, because they are
        // all the same subject at different depths.
        case .presets, .configurePresets, .editPreset: return LarcIcon.presets
        case .controls: return LarcIcon.controls
        case .iconPicker: return LarcIcon.iconPicker
        // A network media box rather than a receiver: `hifireceiver` renders
        // wide and slotted at small sizes, which reads as a bus.
        case .about: return LarcIcon.about
        case .queue: return LarcIcon.queue
        #if LARC_DEV
        case .dev: return LarcIcon.dev
        #endif
        }
    }

    /// "New Preset", "Delete Preset" — built from the noun so a rename reaches
    /// every button that mentions it.
    static func new(_ noun: String) -> String { "New \(noun)" }
    static func delete(_ noun: String) -> String { "Delete \(noun)" }
}

/// The popover's navigation state, owned outside the view hierarchy.
///
/// It lives here rather than in `PopoverView` because `AppDelegate` needs it
/// too: clicking the menu bar icon while a sub-screen is open should go *back*
/// rather than close, and closing the popover has to reset to the root so the
/// next open never resumes somewhere unexpected.
///
// Screens carry fixed transition edges rather than a shared direction: the main
// screen always enters from the left and leaves to the left, and a sub-screen
// always enters from the right and leaves to the right. A direction flag was
// tried and produced the wrong animation half the time, because SwiftUI bakes a
// view's *removal* transition when the view is created — so the outgoing screen
// animated according to whichever direction was current when it appeared, not
// the one taking it away.
@MainActor
final class PopoverNavigation: ObservableObject {
    static let shared = PopoverNavigation()

    /// Where the popover starts, and what closing it returns to.
    ///
    /// Always the main screen, in every build. A `--dev` build used to land on
    /// the gallery, which was right while the gallery was the thing being
    /// worked on and wrong the moment the app itself was — it put a debug
    /// screen between the menu bar and every real control. The Dev row on the
    /// main screen is how you reach it now, and it's still `--dev`-only.
    static var root: [PopoverScreen] { [] }

    @Published private(set) var stack: [PopoverScreen] = PopoverNavigation.root

    /// Set by `AppDelegate`. The popover is `.applicationDefined`, so nothing
    /// dismisses it but us — this is how a view asks for that without reaching
    /// into AppKit itself.
    var requestClose: (() -> Void)?

    /// Set by a screen holding something that isn't valid to leave with — today
    /// only a preset name that duplicates another.
    ///
    /// **Blocks going back, never closing.** Trapping someone in a popover would
    /// be worse than the problem: the way out is to close it, which abandons the
    /// edit, and that's a decision they're entitled to make. Held here rather
    /// than on the screen because three separate routes go back — the header
    /// button, Esc, and the menu bar icon — and a check in one of them is a
    /// check the other two skip.
    @Published var popBlocked = false

    /// Esc: one level back, or closed if already at the root. Matches what a
    /// sheet or a navigation stack does, rather than always closing outright,
    /// which would throw away where you were.
    func escape() {
        if isAtRoot {
            requestClose?()
        } else {
            pop()
        }
    }

    var current: PopoverScreen? { stack.last }
    /// Compared against the configured root rather than emptiness, so a dev
    /// build's landing screen counts as "home" for the menu bar icon's
    /// back-versus-close decision.
    var isAtRoot: Bool { stack == Self.root }

    func push(_ screen: PopoverScreen) {
        stack.append(screen)
    }

    func pop() {
        guard !stack.isEmpty, !popBlocked else { return }
        stack.removeLast()
    }

    /// Back from a dev build's landing screen reaches the main screen, which is
    /// otherwise unreachable there.
    var canPop: Bool { !stack.isEmpty }

    /// Straight to the root, for closing the popover and for the menu bar
    /// icon's "go back" behaviour when several levels deep.
    func reset() {
        // Cleared here as well as by the screen that set it. The screen's
        // `onDisappear` is the normal route, but a flag that can outlive the
        // thing it describes jams every later navigation, and this popover has
        // already been through three rounds of tracked state desyncing from
        // what was actually on screen. Reset is the one call that always runs
        // on close, so it's the right backstop.
        popBlocked = false
        stack = Self.root
    }
}
