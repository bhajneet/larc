import SwiftUI

/// **A mock.** Nothing here reads or writes the device.
///
/// It exists to answer a design question before an implementation question: what
/// would a queue in a 240pt popover even look like, and is it worth building?
///
/// What the device actually offers is UPnP `PlayQueue1` on port 59152 — the
/// service the vendor app uses to build a queue from a browse result. It is
/// self-describing, so `tools/enumerate-upnp.py` can list its real actions
/// without a packet capture; until that's done, the rows below are invented and
/// the header says so.
struct QueueScreen: View {
    /// Deliberately hard-coded and obviously fake. A mock that looked like real
    /// data would be mistaken for it.
    private struct Item: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let playing: Bool
    }

    private let items: [Item] = [
        .init(title: "Faxing Berlin", subtitle: "deadmau5", playing: true),
        .init(title: "Strobe", subtitle: "deadmau5", playing: false),
        .init(title: "Ghosts 'n' Stuff", subtitle: "deadmau5", playing: false),
        .init(title: "Some Chords", subtitle: "deadmau5", playing: false),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: LarcUI.sectionGap) {
            Text("Mock — nothing here talks to the device yet.")
                .font(LarcUI.subtitleFont)
                .foregroundStyle(LarcUI.cautionColor)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: LarcUI.listSpacing) {
                ForEach(items) { item in
                    LarcRow(
                        title: item.title,
                        // The currently-playing row is marked by its glyph
                        // rather than by a badge: the list is narrow, and a
                        // speaker where the note would be says it without
                        // costing width.
                        systemImage: item.playing ? LarcIcon.volume : LarcIcon.presetDefault,
                        subtitle: item.subtitle,
                        selected: item.playing
                    ) {}
                }
            }

            Divider()

            // The three things a queue is *for*, as far as PlayQueue1 suggests.
            // Listed as rows rather than built, so the shape of the screen can be
            // judged before anything is wired.
            VStack(spacing: LarcUI.listSpacing) {
                LarcRow(title: "Clear queue", systemImage: LarcIcon.deletePreset,
                        destructive: true) {}
            }
        }
    }
}
