#if LARC_DEV
import SwiftUI

/// Every component and every icon, on one screen, doing nothing.
///
/// Judging a design one screen at a time means comparing from memory, which is
/// how three row styles drifted apart without anyone noticing. Here they sit
/// beside each other, so a difference in radius, weight or spacing is visible
/// rather than remembered.
///
/// **Nothing here acts.** Buttons press and hover, and that's the point — the
/// feedback is part of what's being judged — but no action reaches a device, and
/// the toggles flip local state that exists only for this screen.
///
/// Compiled only with `-D LARC_DEV` (`./build.sh --dev`), so a release build
/// can't ship it by accident. `check.sh` always defines the flag, so it can't
/// rot either.
struct DevScreen: View {
    @State private var toggles: Set<String> = ["circle-1"]
    @State private var pickedTile = 2
    @State private var pickedOption = 1
    @State private var sampleStep = 4
    @State private var sampleCorrection = "Auto"
    @State private var sampleVolume: Double = 32

    /// The icon each sample uses, stated outright.
    ///
    /// This was a stride over `LarcIcon.allSymbols` — deterministic, but still
    /// *arbitrary*: which glyph a sample got depended on the length of the
    /// catalogue, so adding one icon silently reshuffled every sample on the
    /// screen. A gallery whose contents move when unrelated things change can't
    /// be used to judge whether something changed.
    ///
    /// Written out instead. Each entry is a deliberate choice, and adding an
    /// icon to the catalogue changes nothing here.
    private enum Sample {
        static let pillA = LarcIcon.controls
        static let pillB = LarcIcon.presets
        static let pillWide = LarcIcon.scanNetwork
        static let circleA = LarcIcon.mediaKeys
        static let circleB = LarcIcon.launchAtLogin
        static let pillWithCircles = LarcIcon.scanNetwork
        static let circleC = LarcIcon.network
        static let pillMiddle = LarcIcon.about
        static let circleD = LarcIcon.bluetooth

        /// Four across, one per channel mode — a real set at a real count.
        static let circleRow = [
            LarcIcon.stereo, LarcIcon.leftOnly, LarcIcon.rightOnly, LarcIcon.mono,
        ]
        /// Six, matching the input grid this layout exists to test.
        static let tiles = [
            LarcIcon.network, LarcIcon.lineIn, LarcIcon.bluetooth,
            LarcIcon.optical, LarcIcon.hdmi, LarcIcon.phono,
        ]
        static let rows = [
            LarcIcon.volume, LarcIcon.roomCorrection, LarcIcon.presets,
            LarcIcon.selected, LarcIcon.deviceUnreachable, LarcIcon.controls,
        ]
        static let settingSwitch = LarcIcon.mediaKeys
        static let settingDisabled = LarcIcon.warning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            note("Nothing here does anything. Press away.")

            LarcSection(title: "Artwork", note: "· live sliders") {
                LarcRow(title: "Tuning window…",
                        systemImage: LarcIcon.iconPicker,
                        subtitle: "Opens at launch; this brings it forward") {
                    TuningWindow.show()
                }
            }

            // The one exception, and it says so. For clearing out a session of
            // test presets without touching UserDefaults by hand -- which
            // CLAUDE.md warns against while larc is running.
            LarcSection(title: "Danger", note: "· this one is real") {
                LarcRow(title: "Delete all presets",
                        systemImage: LarcIcon.deletePreset,
                        subtitle: "\(PresetStore.shared.presets.count) stored · no undo",
                        destructive: true) {
                    PresetStore.shared.deleteAll()
                }
            }

            LarcSection(title: "Pill · two up") {
                HStack(spacing: LarcUI.gridSpacing) {
                    LarcPill(title: "Controls", systemImage: Sample.pillA) {}
                    LarcPill(title: "Presets", systemImage: Sample.pillB,
                             subtitle: "Late night") {}
                }
            }

            // Press anything above to see the bounce; these two show what a
            // control looks like while it waits. Both gestures are SF Symbols'
            // own — see GlyphMotion.
            LarcSection(title: "Waiting", note: "· bounce on press, then breathe") {
                HStack(spacing: LarcUI.gridSpacing) {
                    LarcPill(title: "Scanning…", systemImage: Sample.pillWide,
                             subtitle: "Faded label, breathing glyph",
                             isWaiting: true) {}
                }
            }

            LarcSection(title: "Pill · full width") {
                LarcPill(title: "Scan", systemImage: Sample.pillWide,
                         subtitle: "Last scanned 4 minutes ago") {}
            }

            LarcSection(title: "Two circles + pill") {
                HStack(spacing: LarcUI.gridSpacing) {
                    HStack(spacing: LarcUI.gridSpacing) {
                        circle("circle-1", Sample.circleA)
                        circle("circle-2", Sample.circleB)
                    }
                    .frame(width: LarcUI.pillDouble)
                    LarcPill(title: "Scan", systemImage: Sample.pillWithCircles) {}
                        .frame(width: LarcUI.pillDouble)
                }
            }

            LarcSection(title: "Circle · pill · circle") {
                HStack(spacing: LarcUI.gridSpacing) {
                    circle("circle-3", Sample.circleC)
                    LarcPill(title: "Middle", systemImage: Sample.pillMiddle) {}
                    circle("circle-4", Sample.circleD)
                }
            }

            LarcSection(title: "Circles · four up") {
                HStack(spacing: LarcUI.gridSpacing) {
                    ForEach(0..<4, id: \.self) { index in
                        circle("circle-row-\(index)", Sample.circleRow[index])
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            LarcSection(title: "Tiles · labelled", note: "· three up") {
                TileGrid(sampleTiles(labelled: true)) { tile in
                    LarcTile(symbol: tile.symbol, label: tile.label,
                             isActive: tile.index == pickedTile) {
                        pickedTile = tile.index
                    }
                }
            }

            LarcSection(title: "Tile states", note: "· caution, waiting, both") {
                HStack(spacing: LarcUI.gridSpacing) {
                    LarcTile(symbol: Sample.tiles[3], label: "Optical",
                             caution: true,
                             cautionNote: "This didn't take last time.") {}
                    LarcTile(symbol: Sample.tiles[4], label: "HDMI",
                             isWaiting: true) {}
                    LarcTile(symbol: Sample.tiles[5], label: "Phono",
                             isActive: true, isWaiting: true,
                             caution: true, cautionNote: "Both at once.") {}
                    LarcTile(symbol: Sample.tiles[0], label: "Wi-Fi",
                             disabled: true) {}
                }
            }

            LarcSection(title: "Tiles · unlabelled") {
                HStack(spacing: LarcUI.gridSpacing) {
                    ForEach(sampleTiles(labelled: false)) { tile in
                        LarcTile(symbol: tile.symbol,
                                 isActive: tile.index == pickedTile) {
                            pickedTile = tile.index
                        }
                    }
                }
            }

            LarcSection(title: "Rows") {
                VStack(spacing: LarcUI.listSpacing) {
                    LarcRow(title: "Plain row", systemImage: Sample.rows[0]) {}
                    LarcRow(title: "With subtitle", systemImage: Sample.rows[1],
                            subtitle: "Secondary line") {}
                    LarcRow(title: "Leads somewhere", systemImage: Sample.rows[2],
                            showsChevron: true) {}
                    LarcRow(title: "Chosen", systemImage: Sample.rows[3],
                            showsCheckmark: true, selected: true) {}
                    LarcRow(title: "Disabled", systemImage: Sample.rows[4],
                            subtitle: "Not available", disabled: true) {}
                    LarcRow(title: "Destructive", systemImage: LarcIcon.deletePreset, destructive: true) {}
                    LarcRow(title: "With a preset icon", systemImage: Sample.rows[5],
                            subtitle: "Leading view instead of a glyph",
                            leading: AnyView(
                                LarcPresetIcon(symbol: LarcIcon.presetDefault,
                                               tint: .indigo)
                            )) {}
                }
            }

            LarcSection(title: "Setting rows") {
                VStack(spacing: LarcUI.listSpacing) {
                    LarcSettingRow(title: "Volume Step",
                                   systemImage: LarcIcon.volumeStep) {
                        Picker("", selection: $sampleStep) {
                            ForEach(VolumeStepStore.options, id: \.self) { step in
                                Text("\(step)").tag(step)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                    LarcSettingRow(title: "RC",
                                   systemImage: LarcIcon.roomCorrection) {
                        Picker("", selection: $sampleCorrection) {
                            Text("None").tag("None")
                            Text("Auto (Stereo)").tag("Auto")
                            Text("desktop edifiers (L/R)").tag("desk")
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                    LarcSettingRow(title: "A switch", systemImage: Sample.settingSwitch) {
                        Toggle("", isOn: Binding(
                            get: { toggles.contains("switch") },
                            set: { _ in flip("switch") }
                        ))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    }
                    LarcSettingRow(title: "Disabled", systemImage: Sample.settingDisabled, disabled: true) {
                        Text("—").font(LarcUI.rowFont)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            LarcSection(title: "Slider") {
                HStack(spacing: 8) {
                    Image(systemName: LarcIcon.volume)
                        .font(.system(size: LarcUI.iconSingle)).frame(width: LarcUI.iconColumn)
                    Slider(value: $sampleVolume, in: 0...100)
                    Text("\(Int(sampleVolume))")
                        .font(.caption.monospacedDigit())
                        .frame(width: 20, alignment: .trailing)
                }
            }

            LarcSection(title: "Preset icons", note: "· every tint") {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6),
                                   count: 6),
                    spacing: 6
                ) {
                    ForEach(PresetTint.allCases) { tint in
                        LarcPresetIcon(symbol: LarcIcon.presetDefault,
                                       tint: tint)
                    }
                }
            }

            LarcSection(title: "Section note") {
                LarcSection(title: "Nested", note: "· not set") {
                    note("A section with a trailing note.")
                }
            }

            Divider()

            ForEach(LarcIcon.catalogue, id: \.group) { group in
                LarcSection(title: group.group,
                            note: "· \(group.items.count)") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 4),
                                       count: 4),
                        spacing: 6
                    ) {
                        ForEach(group.items, id: \.name) { item in
                            VStack(spacing: 2) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: LarcUI.iconSingle))
                                    .frame(height: 18)
                                Text(item.name)
                                    .font(LarcUI.subtitleFont)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity)
                            .help("\(item.name) · \(item.symbol)")
                        }
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private func circle(_ id: String, _ symbol: String) -> some View {
        LarcCircleToggle(symbol: symbol, label: id, isOn: toggles.contains(id)) {
            flip(id)
        }
    }

    private func flip(_ id: String) {
        if toggles.contains(id) { toggles.remove(id) } else { toggles.insert(id) }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(LarcUI.subtitleFont)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private struct SampleTile: Identifiable {
        let index: Int
        let symbol: String
        let label: String
        var id: Int { index }
    }

    private func sampleTiles(labelled: Bool) -> [SampleTile] {
        (0..<(labelled ? 6 : 4)).map { index in
            SampleTile(index: index, symbol: Sample.tiles[index],
                       label: labelled ? "Item \(index + 1)" : "")
        }
    }
}
#endif
