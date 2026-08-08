import SwiftUI

/// Everything about the device that isn't playback: input, output, channel
/// mode, room correction.
///
/// Grouped this way because they share a property the transport controls don't:
/// you set them and forget them. They belong one level down from the main
/// screen rather than competing with play/pause for the same 240pt.
struct ConfigureScreen: View {
    @ObservedObject private var settings = DeviceSettingsModel.shared
    @ObservedObject private var controller = DeviceController.shared

    var body: some View {
        // Space groups the controls; nothing labels them. See LarcUI.sectionGap.
        VStack(alignment: .leading, spacing: LarcUI.sectionGap) {
            // **Stays for as long as it's true.** This used to be
            // `loading && input == nil`, which is a condition that clears the
            // moment a request finishes — so an unreachable device produced a
            // spinner that flashed on every press and then vanished, implying
            // the problem had gone away. It hadn't. A device that isn't
            // answering is a permanent state until it answers, and the screen
            // should say so the whole time.
            if !controller.reachable {
                unreachableRow
            } else if settings.loading && settings.input == nil {
                loadingRow
            }

            InputGrid(
                isActive: { settings.input == $0 },
                isWaiting: { settings.pending == .input($0) },
                action: { settings.setInput($0) }
            )

            OutputGrid(
                isActive: { settings.output?.rawValue == $0.rawValue },
                isWaiting: { settings.pending == .output($0.rawValue) },
                action: { settings.setOutput($0) }
            )

            ChannelGrid(
                isActive: { settings.channelMode?.rawValue == $0.rawValue },
                isWaiting: { settings.pending == .channel($0.rawValue) },
                action: { settings.setChannelMode($0) }
            )

            // A menu rather than a list of rows. Correction profiles are
            // one-of-many like Volume Step, and a device with several turned
            // this screen into mostly scrolling.
            LarcSettingRow(
                title: "RC", systemImage: LarcIcon.roomCorrection
                            ) {
                Picker("", selection: Binding(
                    get: { settings.currentRoomFitSelection },
                    set: { settings.setRoomFit($0) }
                )) {
                    ForEach(settings.roomFitOptions) { option in
                        Text(option.menuLabel).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                // Sized to the selected profile, capped. Neither `.fixedSize()`
                // nor a fixed width works here: the first hugs the widest *menu
                // item* rather than the chosen one (see LarcUI.popUpWidth), and
                // the second left "None" sitting in a box four times its width.
                .frame(width: min(LarcUI.popUpWidth(for: correctionTitle),
                                  LarcUI.settingControlMaxWidth))
                .animation(.default, value: correctionTitle)
            }

            LarcSettingRow(
                title: "Volume Step", systemImage: LarcIcon.volumeStep
                            ) {
                Picker("", selection: Binding(
                    get: { settings.volumeStep },
                    set: { settings.volumeStep = $0 }
                )) {
                    ForEach(VolumeStepStore.options, id: \.self) { step in
                        Text("\(step)").tag(step)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            if let error = settings.lastError {
                Text(error)
                    .font(LarcUI.subtitleFont)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { settings.loadIfNeeded() }
    }

    /// What the correction picker is showing, so its width can be measured from
    /// the same string the menu button draws.
    private var correctionTitle: String {
        settings.currentRoomFitSelection.menuLabel
    }

    private var loadingRow: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Reading device settings…")
                .font(LarcUI.subtitleFont)
                .foregroundStyle(.secondary)
        }
    }

    /// Names the device and says larc is still trying, because "can't reach it"
    /// on its own reads as final when the poll is in fact retrying every couple
    /// of seconds and will clear this by itself.
    private var unreachableRow: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 1) {
                Text("Can't reach \(controller.selectedDevice?.name ?? "the device")")
                    .font(LarcUI.subtitleFont)
                    .foregroundStyle(LarcUI.errorColor)
                Text("Nothing here will apply until it answers. Still trying…")
                    .font(LarcUI.subtitleFont)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A grid of tiles at the popover's fixed column count.
///
/// Wraps `LazyVGrid` so no screen declares its own columns — three screens
/// doing that independently is how two of them ended up a different width from
/// the third.
struct TileGrid<Data: RandomAccessCollection, Content: View>: View
where Data.Element: Identifiable {
    private let data: Data
    private let content: (Data.Element) -> Content

    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: LarcUI.gridSpacing),
            count: LarcUI.tileColumns
        )
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: LarcUI.gridSpacing) {
            ForEach(data) { element in
                content(element)
            }
        }
    }
}
