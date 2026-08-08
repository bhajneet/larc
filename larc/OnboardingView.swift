import SwiftUI

/// First-launch onboarding. Runs exactly once (`hasCompletedOnboarding`); the
/// menu bar item stays hidden until it finishes.
///
/// Discovery starts the moment onboarding appears (screen 1), not gated
/// behind reaching screen 2 — there's no API to check Local Network
/// permission ahead of time, so starting early means: if it's already
/// granted (e.g. a previous run), the device list may already be populated
/// by the time screen 2 is reached, with no empty-then-populated flash; if
/// not yet granted, this is also what makes the system prompt appear (it
/// may now show over screen 1 rather than screen 2, an accepted tradeoff for
/// not being able to tell those two cases apart ahead of time). Screen 2
/// itself stays blank until 3s have passed since discovery started with
/// nothing found — see `revealHelp`.
///
/// The Accessibility prompt (screen 3) stays behind an explicit tap, since
/// that permission *can* be checked ahead of time (`AXIsProcessTrusted`).
///
/// Media keys are the *last* step because the Accessibility grant only takes
/// effect in a fresh process — the step ends with a restart button rather than
/// pretending the running app can pick the permission up live.
struct OnboardingView: View {
    @ObservedObject var controller = DeviceController.shared
    @ObservedObject var keyTap = MediaKeyTap.shared

    /// `restart == true` means: finish onboarding, then relaunch the app so
    /// the freshly granted Accessibility permission takes effect.
    let onFinished: (_ restart: Bool) -> Void

    private enum Step: Int, CaseIterable {
        case welcome
        case network
        case mediaKeys
    }

    @State private var step: Step = .welcome

    // Network step: when discovery started, and whether screen 2's
    // permission-explanation section has been revealed yet (see network/
    // deviceArea/scheduleHelpReveal).
    @State private var discoveryStartedAt: Date?
    @State private var revealHelp = false

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 520, height: 500)
        .onAppear {
            guard discoveryStartedAt == nil else { return }
            discoveryStartedAt = Date()
            controller.startDiscovery()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .network: network
        case .mediaKeys: mediaKeys
        }
    }

    // MARK: - Step 1

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: LarcIcon.speakers)
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Welcome to Larc!")
                .font(.largeTitle.bold())
            Text("The local audio remote controller")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Adjust volume and issue transport controls for your network streamer from the menubar and keyboard.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Step 2

    private var network: some View {
        VStack(spacing: 12) {
            Image(systemName: LarcIcon.network)
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            Text("Network devices")
                .font(.title.bold())
            deviceArea
        }
        .onAppear { scheduleHelpReveal() }
    }

    /// Fixed-size area so the layout never jumps: blank while we wait to see
    /// what happens, then either the device list or (after 3s with nothing
    /// found) an explanation of what's going on and an escape hatch.
    private var deviceArea: some View {
        VStack(spacing: 8) {
            if controller.devices.isEmpty {
                if revealHelp {
                    Spacer()
                    VStack(spacing: 10) {
                        Text("Apps on macOS 15+ request the privilege to access your network.\nThis permission is required to find your local devices.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Please allow up to 30 seconds for the scan")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Scanning network…")
                                .foregroundStyle(.secondary)
                        }
                        Button("Quit App") {
                            NSApp.terminate(nil)
                        }
                        .controlSize(.small)
                    }
                    Spacer()
                }
                // else: blank — nothing shown yet, avoids a flash for the
                // common case where permission is already granted and
                // devices show up almost immediately.
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(controller.devices) { device in
                            deviceRow(device)
                        }
                    }
                    .padding(.trailing, 4)
                }
            }
        }
        .frame(maxWidth: 400)
        .frame(height: 180)
    }

    /// Reveals the permission-explanation section once 3s have passed since
    /// discovery started (not since screen 2 appeared — if the user lingered
    /// on screen 1, that time already counts) and nothing's been found yet.
    /// No-ops (skips scheduling entirely) if devices already showed up.
    private func scheduleHelpReveal() {
        guard !revealHelp, controller.devices.isEmpty else { return }
        let started = discoveryStartedAt ?? Date()
        let remaining = max(0, 3 - Date().timeIntervalSince(started))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            if controller.devices.isEmpty {
                revealHelp = true
            }
        }
    }

    private func deviceRow(_ device: AudioDevice) -> some View {
        Button {
            controller.selectedID = device.id
        } label: {
            HStack {
                Image(systemName: controller.selectedID == device.id
                      ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text(device.name)
                    Text(device.host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .background(
            controller.selectedID == device.id ? Color.accentColor.opacity(0.12) : .clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    // MARK: - Step 3 (final)

    private var mediaKeys: some View {
        VStack(spacing: 14) {
            Image(systemName: LarcIcon.mediaKeys)
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Media keys")
                .font(.title.bold())
            Text("The play/pause, track, and volume buttons on your keyboard can be redirected from macOS and forwarded to the selected audio device. This behavior can be toggled on and off in the menubar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if keyTap.accessibilityGranted {
                Label("Accessibility access granted", systemImage: LarcIcon.granted)
                    .foregroundStyle(.green)
                Text("After restarting, Larc will be in the menubar.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text("To use this feature, Larc requests accessibility permissions to listen for the media keys on your keyboard.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Enable media keys") {
                    keyTap.requestPermission()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Text("macOS will ask for Accessibility access.\nIf no dialog appears, use System Settings → Privacy & Security → Accessibility.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            // Live re-check while this step is visible; on some macOS versions
            // the in-process check stays stale until relaunch, which is why the
            // restart button does not wait for it.
            while !Task.isCancelled && !keyTap.accessibilityGranted {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                keyTap.refreshPermission()
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") {
                    step = Step(rawValue: step.rawValue - 1) ?? .welcome
                }
            }
            Spacer()
            switch step {
            case .welcome:
                Button("Continue") { step = .network }
                    .buttonStyle(.borderedProminent)
            case .network:
                Button("Continue") { step = .mediaKeys }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.selectedID == nil)
            case .mediaKeys:
                if keyTap.accessibilityGranted {
                    Button("Restart to finish") {
                        // Grant confirmed, so turning capture on is honest;
                        // the fresh launch will install the tap immediately.
                        UserDefaults.standard.set(true, forKey: SettingsKeys.mediaKeysEnabled)
                        onFinished(true)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Skip for now") { onFinished(false) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
