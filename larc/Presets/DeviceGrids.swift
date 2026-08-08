import SwiftUI

/// The three tile grids that both the Controls screen and the preset editor
/// show: input, output, channel mode.
///
/// **Shared so the two screens cannot drift.** They were built independently
/// and had already diverged — different selection logic, different captions,
/// and only one of them showing which outputs the device had refused. What
/// differs between the screens is what a tap *means*, not what the grid looks
/// like, so each takes that as closures and nothing else.
///
/// Selection is a closure rather than a value because the two ask different
/// questions: Controls asks "is the device on this?", the editor asks "does
/// this preset set this?". Same grid, different predicate.

/// Every input the plugin knows about. A fixed set, so it doesn't depend on the
/// device having answered.
struct InputGrid: View {
    let isActive: (AudioInput) -> Bool
    /// Controls uses this while a change is being confirmed; the editor never
    /// waits on anything, so it defaults to never.
    var isWaiting: (AudioInput) -> Bool = { _ in false }
    let action: (AudioInput) -> Void

    var body: some View {
        TileGrid(AudioInput.allCases) { input in
            LarcTile(
                symbol: input.symbolName,
                label: input.displayName,
                isActive: isActive(input),
                isWaiting: isWaiting(input),
                action: { action(input) }
            )
        }
    }
}

/// Outputs the *current device* has, which is why this reads the model rather
/// than taking a list: what a value means is per model, so a grid that didn't
/// know the device could only show numbers.
struct OutputGrid: View {
    @ObservedObject private var settings = DeviceSettingsModel.shared

    let isActive: (AudioOutput) -> Bool
    var isWaiting: (AudioOutput) -> Bool = { _ in false }
    let action: (AudioOutput) -> Void

    var body: some View {
        if settings.availableOutputs.isEmpty {
            // Two different empties: still asking, versus asked and the device
            // has nothing to offer. Saying "none" while a request is in flight
            // would be a claim we can't back.
            Text(settings.isIdentified ? "No outputs reported." : "Reading device…")
                .font(LarcUI.subtitleFont)
                .foregroundStyle(.secondary)
        } else {
            TileGrid(settings.availableOutputs) { output in
                LarcTile(
                    symbol: output.symbolName,
                    label: output.displayName,
                    isActive: isActive(output),
                    isWaiting: isWaiting(output),
                    // Kept and flagged rather than removed: a refusal can be
                    // wrong, and can go stale. See AudioOutput.known(for:).
                    caution: output.wasRefused,
                    cautionNote: "This didn't take last time. It may not be an "
                               + "output this device has — try it and see.",
                    action: { action(output) }
                )
            }
        }
    }
}

/// The four channel modes we can name. An unrecognised value the device reports
/// isn't offered here — `ChannelMode.known` is the verified set — but it still
/// round-trips and displays, so opening this grid can't silently change it.
struct ChannelGrid: View {
    let isActive: (ChannelMode) -> Bool
    var isWaiting: (ChannelMode) -> Bool = { _ in false }
    let action: (ChannelMode) -> Void

    var body: some View {
        TileGrid(ChannelMode.known) { mode in
            LarcTile(
                symbol: mode.symbolName,
                label: mode.displayName,
                isActive: isActive(mode),
                isWaiting: isWaiting(mode),
                action: { action(mode) }
            )
        }
    }
}
