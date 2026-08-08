import SwiftUI

/// The list you reach from the main screen: tap a preset, it applies.
///
/// One tap deep, because that's the whole point — click icon, click Presets,
/// click a preset, click away.
struct PresetsScreen: View {
    @ObservedObject private var store = PresetStore.shared
    @ObservedObject private var settings = DeviceSettingsModel.shared
    @ObservedObject private var navigation = PopoverNavigation.shared

    var body: some View {
        VStack(alignment: .leading, spacing: LarcUI.listSpacing) {
            if store.presets.isEmpty {
                emptyState
            } else {
                ForEach(store.presets) { preset in
                    presetRow(preset) { settings.apply(preset) }
                }
            }

            Divider().padding(.vertical, 4)

            LarcRow(
                title: PopoverScreen.configurePresets.title + "…",
                systemImage: PopoverScreen.controls.symbol
                            ) {
                navigation.push(.configurePresets)
            }
        }
        .onAppear { settings.loadIfNeeded() }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("No presets yet").font(LarcUI.rowFont.weight(.medium))
            Text("A preset applies an input, output, channel mode and room correction in one click.")
                .font(LarcUI.subtitleFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func presetRow(_ preset: Preset, action: @escaping () -> Void) -> some View {
        LarcRow(
            title: preset.name,
            systemImage: preset.symbol,
            subtitle: preset.summary(on: settings.identity?.model),
            leading: AnyView(LarcPresetIcon(symbol: preset.symbol, tint: preset.tint)),
            action: action
        )
    }
}

/// The same list, but tapping edits instead of applying.
///
/// Deliberately identical in layout: the mode changed, not the content, and
/// making them look different would suggest otherwise.
struct ConfigurePresetsScreen: View {
    @ObservedObject private var store = PresetStore.shared
    @ObservedObject private var settings = DeviceSettingsModel.shared
    @ObservedObject private var navigation = PopoverNavigation.shared

    var body: some View {
        VStack(alignment: .leading, spacing: LarcUI.listSpacing) {
            ForEach(store.presets) { preset in
                LarcRow(
                    title: preset.name,
                    systemImage: preset.symbol,
                    subtitle: preset.summary(on: settings.identity?.model),
                    showsChevron: true,
                    leading: AnyView(
                        LarcPresetIcon(symbol: preset.symbol, tint: preset.tint)
                    )
                ) {
                    navigation.push(.editPreset(preset.id))
                }
            }

            if !store.presets.isEmpty {
                Divider().padding(.vertical, 4)
            }

            LarcRow(
                title: PopoverScreen.new(PopoverScreen.presetNoun),
                systemImage: LarcIcon.newPreset
                            ) {
                let preset = store.add()
                navigation.push(.editPreset(preset.id))
            }
        }
    }
}

/// Editing one preset: name, icon, and which settings it applies.
///
/// Every setting defaults to "Any", meaning leave it alone. A preset that only
/// lowers the volume is as valid as one setting everything, and a new preset
/// doing nothing until told to is safer than one that silently rearranges the
/// system.
struct PresetEditScreen: View {
    let presetID: UUID

    @ObservedObject private var store = PresetStore.shared
    @ObservedObject private var settings = DeviceSettingsModel.shared
    @ObservedObject private var navigation = PopoverNavigation.shared

    @State private var draft: Preset?

    var body: some View {
        Group {
            if let draft {
                content(draft)
            } else {
                Text("Preset not found")
                    .font(LarcUI.rowFont)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            draft = store.preset(id: presetID)
            settings.loadIfNeeded()
        }
    }

    private func content(_ preset: Preset) -> some View {
        // Same shape as the Controls screen: shared grids, no captions, space
        // between the groups. The two screens ask different questions of the
        // same controls — "is the device on this?" versus "does this preset set
        // this?" — which is the only thing that differs.
        VStack(alignment: .leading, spacing: LarcUI.sectionGap) {
            nameRow(preset)

            InputGrid(
                isActive: { preset.input == $0 },
                action: { input in edit { $0.input = $0.input == input ? nil : input } }
            )

            OutputGrid(
                isActive: { preset.outputLabel == $0.displayName },
                action: { output in
                    let chosen = preset.outputLabel == output.displayName
                    edit {
                        $0.outputLabel = chosen ? nil : output.displayName
                        // Any legacy number is dropped the moment a name is
                        // chosen, so the two can never disagree.
                        $0.outputValue = nil
                    }
                }
            )

            ChannelGrid(
                isActive: { preset.channelModeValue == $0.rawValue },
                action: { mode in
                    edit {
                        $0.channelModeValue =
                            $0.channelModeValue == mode.rawValue ? nil : mode.rawValue
                    }
                }
            )

            // A menu, matching Controls. It was a list of rows, which made room
            // correction the only setting here that grew the screen with the
            // number of profiles.
            LarcSettingRow(title: "RC", systemImage: LarcIcon.roomCorrection) {
                Picker("", selection: Binding(
                    get: { preset.roomFit },
                    set: { choice in edit { $0.roomFit = choice } }
                )) {
                    ForEach(roomFitChoices, id: \.self) { choice in
                        Text(roomFitLabel(choice)).tag(choice)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: min(LarcUI.popUpWidth(for: roomFitLabel(preset.roomFit)),
                                  LarcUI.settingControlMaxWidth))
            }

            volumeRow(preset)

            Divider().padding(.vertical, 2)

            LarcRow(
                title: PopoverScreen.delete(PopoverScreen.presetNoun),
                systemImage: LarcIcon.deletePreset,
                destructive: true
            ) {
                store.delete(preset)
                navigation.pop()
            }
        }
    }

    /// Icon and name as one control, leading to the screen that edits both.
    ///
    /// Previously the icon was a button and the name an inline text field, so
    /// changing a preset's identity happened in two places depending on which
    /// half you clicked. One target, one destination.
    private func nameRow(_ preset: Preset) -> some View {
        LarcRow(
            title: preset.name,
            systemImage: preset.symbol,
            subtitle: "Icon, colour and name",
            showsChevron: true,
            leading: AnyView(
                LarcPresetIcon(symbol: preset.symbol, tint: preset.tint)
            )
        ) {
            navigation.push(.iconPicker(preset.id))
        }
    }

    /// Every choice the picker offers, in the order it offers them.
    private var roomFitChoices: [PresetRoomFit] {
        [.unchanged, .off] + settings.roomFitProfiles.map { .profile($0.name) }
    }

    /// "—" rather than "Any" or "Unchanged". A dash reads as *nothing chosen*,
    /// which is what `.unchanged` means: the preset won't touch room correction.
    /// "Any" implied a wildcard that would still apply something.
    private func roomFitLabel(_ choice: PresetRoomFit) -> String {
        switch choice {
        case .unchanged: return "—"
        case .off: return "None"
        case .profile(let name): return name
        }
    }

    private func volumeRow(_ preset: Preset) -> some View {
        // Wider than `rowSpacing`: the slider is a second control rather than a
        // continuation of the row above it, and at 4pt it read as crowded
        // against its own label.
        VStack(alignment: .leading, spacing: LarcUI.gridSpacing * 2) {
            // Trailing control, like every other settings row in the popover —
            // a leading toggle here read as a different kind of thing.
            LarcSettingRow(
                title: "Set volume", systemImage: LarcIcon.volume
            ) {
                Toggle("", isOn: Binding(
                    get: { preset.volume != nil },
                    // Seeded from the device's current level, so switching this
                    // on can't itself produce a jump.
                    set: { on in
                        edit { $0.volume = on ? (settings.currentVolume ?? 30) : nil }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            if let volume = preset.volume {
                HStack(spacing: 6) {
                    // No glyph — the row directly above already carries the
                    // volume icon, and a second one restated it. Indented by the
                    // icon column instead, so the slider still starts where a
                    // row's text does rather than hanging off the left margin.
                    Spacer().frame(width: LarcUI.iconColumn)
                    Slider(
                        value: Binding(
                            get: { Double(volume) },
                            // Named rather than $0: the outer closure's value and
                            // the inout Preset would otherwise share it.
                            set: { newValue in
                                edit { $0.volume = Int(newValue.rounded()) }
                            }
                        ),
                        in: 0...100
                    )
                    Text("\(volume)")
                        .font(LarcUI.subtitleFont.monospacedDigit())
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
    }

    // MARK: Choices

    /// One tile, already resolved: what it shows, whether it's on, what it does.
    ///
    /// Flattening each grid to this instead of a switch over a choice enum
    /// keeps "Any" identical across all three groups by construction — it's
    /// just the first item, built the same way each time — and leaves no state
    /// to get out of step.
    /// Edits and saves immediately rather than on a Done button: the popover
    /// dismisses on any outside click, so there is no reliable moment to ask
    /// "save changes?".
    private func edit(_ change: (inout Preset) -> Void) {
        guard var preset = draft else { return }
        change(&preset)
        draft = preset
        store.update(preset)
    }
}

/// Icon and colour, laid out like Apple's Focus and Messages-group pickers: a
/// live preview, the name, a colour grid, then a symbol grid.
///
/// Apple's own picker is private API, so this is a lookalike rather than the
/// real control.
struct IconPickerScreen: View {
    let presetID: UUID

    @ObservedObject private var store = PresetStore.shared
    @ObservedObject private var navigation = PopoverNavigation.shared
    @State private var draft: Preset?
    /// The name this screen opened with, so a duplicate can be abandoned.
    ///
    /// The field writes straight through to the store, so by the time a name is
    /// known to collide it has already been saved. Keeping the original is what
    /// makes "close the popover and the change is lost" true rather than
    /// aspirational.
    @State private var originalName = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    /// A name that duplicates another preset's. Reported under the field and
    /// blocks going back; it does not block closing the popover.
    private var duplicateName: Bool {
        guard let draft else { return false }
        return store.nameIsTaken(draft.name, excluding: presetID)
    }

    var body: some View {
        Group {
            if let draft {
                content(draft)
            } else {
                Text("Preset not found")
                    .font(LarcUI.rowFont)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            draft = store.preset(id: presetID)
            originalName = draft?.name ?? ""
        }
        .onChange(of: duplicateName) { navigation.popBlocked = duplicateName }
        .onDisappear {
            // Reached only by the popover closing, since back is blocked while
            // the name duplicates another. The edit is abandoned rather than
            // corrected: renaming someone's text on their behalf produced
            // "Preset 2 2", which is a name nobody typed.
            if duplicateName { store.rename(id: presetID, to: originalName) }
            navigation.popBlocked = false
        }
    }

    private func content(_ preset: Preset) -> some View {
        VStack(spacing: 10) {
            LarcPresetIcon(symbol: preset.symbol, tint: preset.tint, size: LarcUI.presetTileLarge)

            TextField("Name", text: Binding(
                get: { preset.name },
                set: { newValue in edit { $0.name = newValue } }
            ))
            .textFieldStyle(.roundedBorder)
            .font(LarcUI.rowFont)
            .multilineTextAlignment(.center)

            // Red, not the caution orange: this one blocks going back, and
            // orange in this popover marks things you can ignore. See
            // LarcUI.errorColor.
            //
            // Generic rather than naming the preset — the offending name is in
            // the field directly above, so repeating it says nothing and grows
            // the line for no reason.
            if duplicateName {
                Text("A preset with this name already exists")
                    .font(LarcUI.subtitleFont)
                    .foregroundStyle(LarcUI.errorColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(PresetTint.allCases) { tint in
                    Button { edit { $0.tint = tint } } label: {
                        Circle()
                            .fill(tint.color)
                            .frame(width: 24, height: 24)
                            // **The one ring that stays.** Everywhere else a
                            // selected shape changes its fill, so a ring on top
                            // was saying the same thing twice. Here the fill
                            // *is* the value being chosen — a colour cannot also
                            // be its own selection state — so a ring is the only
                            // mark available. Neutral rather than accent, and
                            // held off the swatch by 3pt, so it reads against
                            // all six tints without becoming a seventh colour.
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        Color.primary.opacity(0.7),
                                        lineWidth: preset.tint == tint ? 2 : 0
                                    )
                                    .padding(-3)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(PresetSymbols.all, id: \.self) { symbol in
                    Button { edit { $0.symbol = symbol } } label: {
                        // Selected reads exactly as it does everywhere else —
                        // solid fill, white mark — with the preset's own tint
                        // standing in for the accent, since that is the colour
                        // this icon will actually be. No ring: the fill says it.
                        LarcGlyph(symbol: symbol, size: LarcUI.iconSingle, box: 24)
                            .frame(height: 24)
                            .foregroundStyle(
                                preset.symbol == symbol
                                ? LarcUI.selectedForeground : .primary
                            )
                            .background {
                                Circle().fill(
                                    preset.symbol == symbol
                                    ? preset.tint.color
                                    : Color.primary.opacity(0.06)
                                )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func edit(_ change: (inout Preset) -> Void) {
        guard var preset = draft else { return }
        change(&preset)
        draft = preset
        store.update(preset)
    }
}
