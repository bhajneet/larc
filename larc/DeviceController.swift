import AppKit
import Combine
import Foundation

/// Central state: device list (discovered + manual), the selected device's
/// plugin, status polling, and user-initiated control actions.
@MainActor
final class DeviceController: ObservableObject {
    static let shared = DeviceController()

    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var status: PlayerStatus?
    @Published private(set) var reachable = true

    /// The input the device last reported, **held across idle**.
    ///
    /// `getPlayerStatus.mode` goes to -1 whenever nothing is playing — including
    /// while optical audio is genuinely passing through and the device is
    /// dozing — so `status?.input` blinks out constantly. Stopping playback does
    /// not unplug a cable, so the last real answer stands until the device gives
    /// a different one. Cleared only when the selected device changes, where the
    /// previous answer belonged to different hardware.
    @Published private(set) var currentInput: AudioInput?

    private var wakeObserver: NSObjectProtocol?
    /// Volume value to flash in the menu bar while the user is adjusting it;
    /// nil once the adjustment settles (1.5 s after the last change).
    @Published private(set) var volumeFlash: Int?
    /// True while a rescan window is open (browse results keep streaming in;
    /// ~10 s is treated as "the scan").
    @Published private(set) var scanning = false
    @Published private(set) var lastScanAt: Date?
    /// Bumped on every previous/next-track call, from a click or a hotkey —
    /// PopoverView observes these to flash the transport buttons, since
    /// there's no persistent "previous/next was pressed" state to key an
    /// animation off, unlike play/pause's `status.state`.
    @Published private(set) var previousTrackTrigger = UUID()
    @Published private(set) var nextTrackTrigger = UUID()
    /// Never restored directly from a persisted value — always re-earned via
    /// `mergeDevices()` matching `perNetworkDeviceID[currentNetworkFingerprint]`
    /// against what's actually been discovered. That's what keeps a stale
    /// selection from an old network from ever being shown as selected.
    @Published var selectedID: String? {
        didSet {
            if let id = selectedID, let fp = currentNetworkFingerprint {
                perNetworkDeviceID[fp] = id
                persistPerNetworkDeviceID()
            }
            rebuildPlugin()
        }
    }

    /// Published so views can pause work that's pointless while hidden — the
    /// popover's hosting view stays alive across open/close, so anything
    /// animating (the marquee) would otherwise keep running unseen.
    @Published var popoverOpen = false {
        didSet {
            guard popoverOpen != oldValue else { return }
            schedulePolling()
            if popoverOpen {
                refreshNetworkFingerprint()
                pollNow()
            }
        }
    }

    /// The artwork tuning window is on screen.
    ///
    /// It watches `status.albumArtURL` to know when to reload a cover, and the
    /// popover is almost always closed while it's being used — so it was
    /// waiting out the idle 10s interval for every track change, which is most
    /// of a minute across a handful of covers. Polls faster than the popover
    /// does, because the *only* thing that window is for is looking at the
    /// artwork of whatever is playing right now.
    @Published var tuningWindowOpen = false {
        didSet {
            guard tuningWindowOpen != oldValue else { return }
            schedulePolling()
            if tuningWindowOpen { pollNow() }
        }
    }

    private var discovered: [AudioDevice] = []
    /// Results arriving during a rescan window are buffered here and applied
    /// when the scan ends — the visible list (and the selected device) must
    /// not churn mid-scan.
    private var pendingDiscovered: [AudioDevice]?
    private var manual: [AudioDevice] = []
    private var plugin: LinkplayPlugin?

    /// Read-only access for screens that need capabilities rather than
    /// playback state — input, output, channel mode, room correction. Those
    /// aren't polled here because they change only when someone changes them,
    /// so carrying them in the 2 s poll would cost four requests forever to
    /// keep a screen fresh that is usually closed. See `DeviceSettingsModel`.
    var currentPlugin: LinkplayPlugin? { plugin }
    private var pollTimer: Timer?

    // Volume interaction state: while the user drags the slider (or shortly
    // after any local change) polled values must not fight the local value.
    private var draggingVolume = false
    private var lastLocalChangeAt = Date.distantPast
    /// When a transport command was last issued locally. Guards `status.state`
    /// against transient poll results the same way `lastLocalChangeAt` guards
    /// volume against slider fights.
    private var lastTransportChangeAt = Date.distantPast
    /// Longer than the volume guard's 1.5 s because a device changing tracks
    /// can sit in stopped/loading for a second or more before audio starts.
    private let transportGuard: TimeInterval = 3
    private var pendingVolume: Int?
    private var volumeSendScheduled = false
    private var volumeFlashClearTask: Task<Void, Never>?

    private var discoveryStarted = false

    // Per-network device memory (see NetworkFingerprint). currentNetworkFingerprint
    // is recomputed at launch and on every popover open — a nil-to-value
    // transition or a changed value both count as "switched networks".
    private var currentNetworkFingerprint: String?
    private var perNetworkDeviceID: [String: String] = [:]

    private init() {
        manual = Self.loadManualDevices()
        perNetworkDeviceID = Self.loadPerNetworkDeviceID()
        currentNetworkFingerprint = NetworkFingerprint.current()
        mergeDevices()
        rebuildPlugin()
        schedulePolling()

        // The poll timer does not run while the Mac is asleep, so on wake
        // `status` can be hours old — and volume stepping is *relative* to it,
        // sending `vol:(cached + step)` as an absolute value because Linkplay
        // has no relative command. A stale cache therefore doesn't just display
        // the wrong number, it overwrites the device with it: cache 20 against a
        // device at 45 means the first press sets 21. It can jump upward just as
        // easily, which is the direction that matters.
        //
        // One poll per wake, not a new interval. The network may also have
        // changed while asleep, so the fingerprint is rechecked the same way
        // opening the popover does.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshNetworkFingerprint()
                self.pollNow()
            }
        }
    }

    /// Detects a network switch (differing gateway MAC) and, if one occurred,
    /// drops the stale device list/selection immediately and kicks off a
    /// fresh scan — `rescan()` already gives visible "Scanning…" feedback
    /// while it converges, rather than a flat "No devices found" that could
    /// just mean "give it a second".
    private func refreshNetworkFingerprint() {
        guard let fp = NetworkFingerprint.current() else { return }
        guard let previous = currentNetworkFingerprint else {
            // No confident earlier reading (e.g. ARP wasn't warm yet at
            // launch, before Local Network permission was even resolved) —
            // adopt this one without treating it as a switch. Backfill the
            // per-network memory for whatever's already selected, since the
            // earlier assignment (e.g. during onboarding) couldn't record
            // itself against a fingerprint that didn't exist yet.
            currentNetworkFingerprint = fp
            if let id = selectedID {
                perNetworkDeviceID[fp] = id
                persistPerNetworkDeviceID()
            }
            return
        }
        guard fp != previous else { return }
        currentNetworkFingerprint = fp
        discovered = []
        pendingDiscovered = nil
        devices = []
        selectedID = nil
        if discoveryStarted {
            rescan()
        }
    }

    /// Begins mDNS discovery. Deliberately not called from init: during
    /// onboarding this must not run until the user taps "Find my devices", so
    /// the macOS Local Network prompt appears in context.
    func startDiscovery() {
        guard !discoveryStarted else { return }
        discoveryStarted = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if lastScanAt == nil { lastScanAt = Date() }
        }
        if let count = Self.mockDeviceCount {
            injectMockDevices(count: count)
            return
        }
        LinkplayDiscoverer.shared.start { [weak self] found in
            Task { @MainActor in
                guard let self else { return }
                if self.scanning {
                    self.pendingDiscovered = found
                } else {
                    self.discovered = found
                    self.mergeDevices()
                }
            }
        }
    }

    // MARK: - Mock devices (UI testing)

    /// `open build/Larc.app --args --mock-devices 12` replaces real discovery
    /// with N fake devices (staggered arrival) to exercise long device lists.
    /// `--mock-devices 0` injects none at all, forcing (and holding) the
    /// no-device-selected state for UI testing.
    private static var mockDeviceCount: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "--mock-devices") else { return nil }
        if args.indices.contains(idx + 1), let n = Int(args[idx + 1]) {
            return min(max(n, 0), 50)
        }
        return 12
    }

    private func injectMockDevices(count: Int) {
        let names = [
            "WiiM Amp Nook", "WiiM Ultra Living Room", "Kitchen Mini",
            "Bedroom Streamer with an Unreasonably Long Name", "Office",
            "Garage Amp", "Patio Speaker", "Guest Room WiiM Pro Plus",
        ]
        Task { @MainActor in
            for i in 0..<count {
                try? await Task.sleep(nanoseconds: 300_000_000)
                let name = "\(names[i % names.count]) #\(i + 1)"
                discovered.append(AudioDevice(
                    id: "mock-\(i)",
                    name: name,
                    host: "192.0.2.\(100 + i)", // RFC 5737 TEST-NET-1: never routable
                    source: .discovered
                ))
                mergeDevices()
            }
        }
    }

    // MARK: - Device list

    var selectedDevice: AudioDevice? {
        devices.first { $0.id == selectedID }
    }

    @discardableResult
    func addManualDevice(host: String, name: String, kind: DeviceKind = .linkplay) -> AudioDevice? {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        guard !trimmedHost.isEmpty else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let device = AudioDevice(
            id: "manual-" + trimmedHost,
            name: trimmedName.isEmpty ? trimmedHost : trimmedName,
            host: trimmedHost,
            source: .manual,
            kind: kind
        )
        manual.removeAll { $0.host == trimmedHost }
        manual.append(device)
        persistManualDevices()
        mergeDevices()
        if selectedID == nil { selectedID = device.id }
        return device
    }

    func removeManualDevice(_ device: AudioDevice) {
        manual.removeAll { $0.id == device.id }
        persistManualDevices()
        mergeDevices()
    }

    func rescan() {
        guard !scanning else { return }
        scanning = true
        if Self.mockDeviceCount == nil {
            LinkplayDiscoverer.shared.restart()
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            scanning = false
            if let fresh = pendingDiscovered {
                pendingDiscovered = nil
                discovered = fresh
                // mergeDevices keeps the current selection whenever the scan
                // found it again.
                mergeDevices()
            }
            lastScanAt = Date()
        }
    }

    private func mergeDevices() {
        let discoveredHosts = Set(discovered.map { $0.host })
        var merged = discovered + manual.filter { !discoveredHosts.contains($0.host) }
        // If the selected device just isn't in this update, keep showing it
        // rather than losing the selection (or silently handing control to a
        // different device) — mDNS browse sessions report an explicit
        // "removed" event when an interface drops (e.g. leaving Wi-Fi range,
        // airplane mode), even though the device is still the one the user
        // wants. Polling will mark it unreachable ("Device not responding")
        // until it's seen again; the stable mDNS uuid reattaches it cleanly.
        // BUT: only while nothing else has claimed its last-known IP — if a
        // different discovered device now sits at that address (DHCP handed
        // it out again), trusting the stale entry would mean silently
        // controlling the wrong physical device, which is worse than just
        // dropping the selection.
        if let id = selectedID, !merged.contains(where: { $0.id == id }) {
            if let stillKnown = devices.first(where: { $0.id == id }), !discoveredHosts.contains(stillKnown.host) {
                merged.append(stillKnown)
            } else {
                // Either never seen this session, or its last-known IP now
                // belongs to a different discovered device. Don't leave
                // selectedID dangling on something absent from `devices` —
                // the picker's selection wouldn't match any tag (not nil, so
                // the "Choose a device" placeholder wouldn't show either).
                selectedID = nil
            }
        }
        devices = merged
        if selectedID == nil,
           let fp = currentNetworkFingerprint,
           let remembered = perNetworkDeviceID[fp],
           devices.contains(where: { $0.id == remembered }) {
            // Only auto-select a device this network has actually confirmed
            // via discovery — never a blind "pick the first one", and never
            // a device remembered for a *different* network.
            selectedID = remembered
        }
        // Unconditional: covers the normal match (no-op if unchanged), the
        // stale ghost getting dropped above (clears the plugin so polling
        // stops hitting a reused IP), and the auto-select just above
        // (redundant with its didSet, but harmless).
        rebuildPlugin()
    }

    private func rebuildPlugin() {
        let device = selectedDevice
        guard plugin?.device.id != device?.id || plugin?.device.host != device?.host else { return }
        plugin = device.map { LinkplayPlugin(device: $0) }

        // Reset to the unrestricted scale, then ask. A cap belonging to the
        // outgoing device would otherwise shorten the incoming one's slider
        // until its own identification came back.
        maxVolume = 100
        if let plugin {
            Task { @MainActor in
                _ = await plugin.identify()
                guard plugin === self.plugin else { return }
                maxVolume = plugin.cachedMaxVolume
            }
        }

        // Anything in flight belonged to the outgoing device, and both guards
        // must be cleared or they'd hold ITS values over the incoming device's
        // first poll — which is the one reading we actually want to win.
        pendingVolume = nil
        draggingVolume = false
        lastLocalChangeAt = .distantPast
        lastTransportChangeAt = .distantPast
        // Unlike `status`, this is cleared: an input held from the outgoing
        // device would gate the incoming one's media keys on hardware it isn't.
        currentInput = nil

        // Deliberately NOT `status = nil` when switching between devices.
        //
        // Clearing it left the UI with no data for the one round trip until the
        // first poll: `displayVolume` fell back to `?? 0` and `showsAsPlaying`
        // to false, so the slider slammed to zero and the pause glyph became
        // play, then both snapped to the real values a moment later. Keeping the
        // outgoing device's status as a placeholder means nothing moves until
        // there's something real to move to. It is briefly the wrong device's
        // numbers, but it's stationary and gone within a round trip, which
        // reads far better than a double jump.
        //
        // With no device at all there is genuinely nothing to show, so clear.
        if plugin == nil {
            status = nil
        }
        reachable = true
        if plugin != nil { pollNow() }
    }

    private static func loadManualDevices() -> [AudioDevice] {
        guard let data = UserDefaults.standard.data(forKey: SettingsKeys.manualDevices),
              let list = try? JSONDecoder().decode([AudioDevice].self, from: data) else { return [] }
        return list
    }

    private func persistManualDevices() {
        if let data = try? JSONEncoder().encode(manual) {
            UserDefaults.standard.set(data, forKey: SettingsKeys.manualDevices)
        }
    }

    private static func loadPerNetworkDeviceID() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: SettingsKeys.perNetworkDeviceID),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    private func persistPerNetworkDeviceID() {
        if let data = try? JSONEncoder().encode(perNetworkDeviceID) {
            UserDefaults.standard.set(data, forKey: SettingsKeys.perNetworkDeviceID)
        }
    }

    // MARK: - Polling

    private func schedulePolling() {
        pollTimer?.invalidate()
        let interval: TimeInterval = tuningWindowOpen ? 1 : (popoverOpen ? 2 : 10)
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                DeviceController.shared.pollNow()
            }
        }
    }

    func pollNow() {
        guard let plugin else { return }
        Task { @MainActor in
            do {
                let fresh = try await plugin.getStatus()
                guard plugin === self.plugin else { return }
                reachable = true
                apply(fresh)
            } catch {
                guard plugin === self.plugin else { return }
                reachable = false
            }
        }
    }

    private func apply(_ fresh: PlayerStatus) {
        var merged = fresh
        if draggingVolume || Date().timeIntervalSince(lastLocalChangeAt) < 1.5 {
            merged.volume = pendingVolume ?? status?.volume ?? fresh.volume
        } else {
            pendingVolume = nil
        }
        // Same idea for transport, but filtered rather than blanket. A device
        // changing tracks reports stopped or loading in the gap before audio
        // starts, which used to overwrite the local state and flip the icon to
        // play and back.
        //
        // Only **unsettled** reports are suppressed. Holding the local state for
        // the whole window regardless meant that after pausing and skipping, the
        // device's "playing" was ignored for up to 3 s — so the play glyph, and
        // the marquee with it, lagged well behind the audio. A settled report is
        // the device telling us something definite; there's no reason to argue
        // with it.
        //
        // `.stopped` is treated as unsettled, so pressing play with nothing
        // queued still reverts after the window rather than instantly. That
        // revert is wanted: it's the device honestly reporting it can't play.
        if let local = status?.state,
           !fresh.state.isSettled,
           Date().timeIntervalSince(lastTransportChangeAt) < transportGuard {
            merged.state = local
        }
        status = merged

        // nil here means idle, not "no input" — see AudioInput.init(mode:).
        if let input = merged.input { currentInput = input }
    }

    // MARK: - Volume

    var displayVolume: Double {
        Double(pendingVolume ?? status?.volume ?? 0)
    }

    /// The highest volume this device will accept, from `getStatusEx`'s
    /// `max_volume`.
    ///
    /// The slider runs 0…this rather than 0…100, so a device capped at 40 shows
    /// 20 as half full rather than a fifth. Showing a scale the hardware won't
    /// honour means the slider stops responding partway along, which reads as a
    /// bug in larc.
    /// `getStatusEx.max_volume`, kept for diagnostics only.
    ///
    /// **Never clamp a slider to this.** It is a *scaling* cap, not a range
    /// limit: set it to 50 on a WiiM and the device still reports and accepts
    /// 0–100, with 100 meaning whatever 50 used to. Clamping the slider to it
    /// therefore stopped larc reaching the top of a range the device was still
    /// offering — the app could only get halfway up its own volume.
    ///
    /// What the setting genuinely implies is that a *step* of 3 covers less
    /// actual loudness on a capped device, which is an argument for a larger
    /// volume step, not a shorter slider.
    @Published private(set) var maxVolume: Int = 100

    func userSetVolume(_ value: Double) {
        let volume = min(100, max(0, Int(value.rounded())))
        pendingVolume = volume
        lastLocalChangeAt = Date()
        if var s = status {
            s.volume = volume
            status = s
        }
        flashVolume(volume)
        scheduleVolumeSend()
    }

    private func flashVolume(_ volume: Int) {
        volumeFlash = volume
        volumeFlashClearTask?.cancel()
        volumeFlashClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            volumeFlash = nil
        }
    }

    func volumeDragChanged(_ editing: Bool) {
        draggingVolume = editing
        if !editing, let volume = pendingVolume {
            sendVolume(volume)
        }
    }

    func stepVolume(_ direction: Int) {
        Task { @MainActor in
            var base = pendingVolume ?? status?.volume
            if base == nil, let plugin {
                base = try? await plugin.getStatus().volume
            }
            guard let base else { return }
            let step = VolumeStepStore.step(for: selectedID)
            userSetVolume(Double(base + direction * step))
        }
    }

    /// Coalesces rapid slider/key changes into at most ~7 requests per second.
    private func scheduleVolumeSend() {
        guard !volumeSendScheduled else { return }
        volumeSendScheduled = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            volumeSendScheduled = false
            if let volume = pendingVolume {
                sendVolume(volume)
            }
        }
    }

    private func sendVolume(_ volume: Int) {
        guard let plugin else { return }
        Task { @MainActor in
            do {
                try await plugin.setVolume(volume)
                reachable = true
            } catch {
                reachable = false
            }
        }
    }

    // MARK: - Transport & mute

    func toggleMute() {
        guard let plugin else { return }
        let target = !(status?.muted ?? false)
        if var s = status {
            s.muted = target
            status = s
        }
        Task { @MainActor in
            do {
                try await plugin.setMute(target)
                reachable = true
            } catch {
                reachable = false
            }
        }
    }

    /// Jumps to a position, then polls soon so the bar settles on what the
    /// device actually did rather than on what we asked for.
    func seek(to seconds: Double) {
        guard let plugin = currentPlugin else { return }
        status?.position = seconds
        Task {
            try? await plugin.seek(to: seconds)
            pollSoon()
        }
    }

    func playPause() {
        guard let plugin else { return }
        if var s = status {
            s.state = s.state.showsAsPlaying ? .paused : .playing
            status = s
        }
        beginTransportChange()
        Task { @MainActor in
            try? await plugin.playPause()
            pollSoon()
        }
    }

    func nextTrack() {
        guard let plugin else { return }
        nextTrackTrigger = UUID()
        beginTransportChange()
        Task { @MainActor in
            try? await plugin.next()
            pollSoon()
        }
    }

    func previousTrack() {
        guard let plugin else { return }
        previousTrackTrigger = UUID()
        beginTransportChange()
        Task { @MainActor in
            try? await plugin.previous()
            pollSoon()
        }
    }

    /// Marks a transport command as just-issued, so `apply(_:)` holds the
    /// current state through the device's transient stopped/loading report
    /// during a track change.
    ///
    /// Deliberately does **not** force `.playing`. It used to, which fixed the
    /// icon flipping while skipping during playback but was wrong whenever the
    /// user had paused: hitting next/prev then claimed playback had started,
    /// and resumed the marquee, before the next track had even loaded.
    ///
    /// Preserving whatever state we already had covers both directions —
    /// playing stays playing, paused stays paused — and the poll corrects us
    /// once the guard expires if the device disagrees. The guard was always
    /// what fixed the original flicker; asserting `.playing` on top of it was
    /// never doing the work.
    private func beginTransportChange() {
        lastTransportChangeAt = Date()
    }

    private func pollSoon() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            pollNow()
        }
    }
}
