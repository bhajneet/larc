import SwiftUI

/// Everything that isn't controlling a device: what larc is, where to find it,
/// how to support it, and what it currently sees.
///
/// A destination rather than rows on the main screen. None of it is needed
/// while adjusting the volume, and the main screen is for things you reach for
/// often.
struct AboutScreen: View {
    @ObservedObject private var controller = DeviceController.shared
    @ObservedObject private var settings = DeviceSettingsModel.shared

    /// Placeholders until the repository is public and a funding platform is
    /// chosen — see the shipping checklist. Wrong links are worse than absent
    /// ones, so these open nothing until they're real.
    private static let repositoryURL: URL? = nil
    private static let donateURL: URL? = nil

    private var version: String {
        let short = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return short ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // No logo or app-name block. The header already says "About"
            // one line above, so repeating the name, the tagline and an icon
            // filled a third of the screen restating what the user just read.
            LarcSection(title: "Device") {
                VStack(spacing: LarcUI.listSpacing) {
                    detail("Model", settings.identity?.displayName ?? "—")
                    detail("Firmware", settings.identity?.firmware ?? "—")
                    detail("Address", controller.selectedDevice?.host ?? "—")
                    // Belongs with the device it describes, not with the
                    // project links.
                    LarcRow(
                        title: "Diagnostics",
                        systemImage: LarcIcon.diagnostics,
                        subtitle: diagnosticsSubtitle
                                            ) {
                        copyDiagnostics()
                    }
                }
            }

            LarcSection(title: "larc \(version)") {
                VStack(spacing: LarcUI.listSpacing) {
                    LarcRow(
                        title: "Source on GitHub",
                        systemImage: LarcIcon.sourceCode,
                        subtitle: "MIT licensed",
                        disabled: Self.repositoryURL == nil
                    ) {
                        open(Self.repositoryURL)
                    }
                    LarcRow(
                        title: "Leave a tip",
                        systemImage: LarcIcon.tip,
                        subtitle: "larc is free, and stays free",
                        disabled: Self.donateURL == nil
                    ) {
                        open(Self.donateURL)
                    }
                }
            }
        }
        .onAppear { settings.loadIfNeeded() }
    }

    /// Confirmation replaces the row's own subtitle for a moment rather than
    /// appearing as a new line. A row that grows a sibling shifts everything
    /// below it, and the feedback belongs to the thing that was clicked.
    @State private var copiedMessage: String?

    private var diagnosticsSubtitle: String {
        copiedMessage ?? "Copy what larc knows about this device"
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(spacing: LarcUI.rowSpacing) {
            Text(label)
                .font(LarcUI.rowFont)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(LarcUI.rowFont)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    /// Copies a device profile to the clipboard.
    ///
    /// Deliberately the same structured export used for contributions, not a
    /// free-form dump: it carries model, firmware and observed capabilities and
    /// **cannot** carry an address, a uuid or a token, because the type has no
    /// field for one. Captures taken while building this contained a Plex
    /// token, and a dump-what-we-know diagnostic would have leaked it.
    private func copyDiagnostics() {
        guard let identity = settings.identity,
              let export = DeviceProfileExport.build(
                identity: identity,
                labels: [:],
                workingInputs: settings.input.map { [$0] } ?? [],
                channelModes: settings.channelMode.map { [$0] } ?? []
              )
        else {
            flash("No device to report on yet")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(export.shareableText, forType: .string)
        flash("Copied")
    }

    /// Shows a message in place of the subtitle, then restores it. Generation-
    /// guarded so a second click doesn't get its message cut short by the first
    /// click's timer.
    @State private var flashGeneration = 0

    private func flash(_ message: String) {
        flashGeneration += 1
        let generation = flashGeneration
        copiedMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard generation == flashGeneration else { return }
            copiedMessage = nil
        }
    }
}
