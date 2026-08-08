import Combine
import SwiftUI

/// Live device settings for the Configure screen: input, output, channel mode
/// and room correction.
///
/// Separate from `DeviceController`, which owns the things that need polling
/// twice a second — transport, volume, artwork. These change rarely and only
/// when someone asks, so they're loaded when a screen opens rather than polled,
/// and that keeps a busy poll loop from carrying four more requests forever.
///
/// Every setter here is optimistic then verified: the UI moves immediately, the
/// plugin confirms by reading back, and a refused change reverts. That matters
/// on this hardware specifically — it answers `OK` to values it silently
/// ignores, so a UI trusting the reply would show a switch that never happened.
@MainActor
final class DeviceSettingsModel: ObservableObject {
    static let shared = DeviceSettingsModel()

    @Published var identity: DeviceIdentity?
    @Published var input: AudioInput?
    @Published var output: AudioOutput?
    @Published var channelMode: ChannelMode?
    @Published var roomFit: RoomFitState?
    @Published var roomFitProfiles: [RoomFitProfile] = []

    /// A change that has been in flight long enough to be worth showing, so the
    /// control that started it can breathe until it lands.
    ///
    /// A readback is given six seconds — the device doesn't always apply a
    /// change before it answers, and giving up early writes down a refusal. Six
    /// seconds of a control that visibly isn't finished is fine; six seconds of
    /// one that looks finished is not.
    ///
    /// **Appears late, after `breathAfter`.** Almost every change confirms on
    /// the first readback, so showing this immediately would flash a breath on
    /// every single press — motion that means "still working" would come to mean
    /// nothing at all. Silence for a moment and then a breath says the useful
    /// thing: this one is taking longer than it should.
    ///
    /// Single, not a set: these are sequential user actions, and a second press
    /// replaces the first rather than queueing behind it.
    @Published private(set) var pending: PendingChange?

    /// How long a change may take before it's worth saying so.
    private static let breathAfter: TimeInterval = 1.5

    /// Identifies the change currently in flight, so a slow one that has already
    /// been superseded doesn't start breathing on top of its replacement.
    private var inFlight: UUID?

    enum PendingChange: Equatable {
        case input(AudioInput)
        case output(Int)
        case channel(Int)
        case roomFit
    }

    @Published var loading = false
    /// Set when a change was refused, so a screen can say so rather than
    /// silently snapping back — which would look like a bug.
    @Published var lastError: String?

    private var loadedForDeviceID: String?
    private var deviceObserver: AnyCancellable?
    private var inputObserver: AnyCancellable?

    private var plugin: LinkplayPlugin? { DeviceController.shared.currentPlugin }

    /// Starts loading as soon as a device is selected, rather than when a
    /// settings screen opens.
    ///
    /// Identification is one round trip, and the Controls screen can't draw
    /// honestly without it — so it should already be in flight by the time
    /// anyone navigates there. Selecting a device on the main screen is the
    /// moment that becomes knowable.
    private init() {
        deviceObserver = DeviceController.shared.$selectedID
            .removeDuplicates()
            .sink { [weak self] _ in
                // Next run loop: `selectedID`'s publisher fires on willSet, so
                // the controller hasn't rebuilt its plugin for the new device
                // yet and we'd load against the outgoing one.
                DispatchQueue.main.async { self?.loadIfNeeded() }
            }

        // Input is the one setting the DEVICE changes on its own — an alarm or
        // auto-sense switches to Wi-Fi with nobody at the Mac — so a value read
        // once when the screen opened goes quietly stale and the screen keeps
        // claiming Optical for hours.
        //
        // It needs no request of its own: `currentInput()` reads
        // `getPlayerStatus`, which DeviceController already polls, and
        // `PlayerStatus.input` is that same field parsed. So this tracks the
        // existing poll instead of adding a seventh round trip.
        // `currentInput` rather than `status?.input`: the controller already
        // holds the last real answer across idle, so the Controls screen keeps
        // its tile lit when playback stops instead of clearing every selection.
        inputObserver = DeviceController.shared.$currentInput
            .removeDuplicates()
            .sink { [weak self] reported in
                guard let self else { return }
                // A local change owns the value until it settles. Afterwards the
                // device's own report is the truth — including when it refused,
                // which is the case `revert()` alone can't see.
                if case .input = self.pending { return }
                self.input = reported
            }
    }

    /// Loads everything a settings screen needs, once per device.
    ///
    /// `force` is for after a change that could invalidate more than it set —
    /// switching input, for instance, can move which correction slot applies.
    func loadIfNeeded(force: Bool = false) {
        guard let plugin else { return }
        let deviceID = plugin.device.id
        guard force || loadedForDeviceID != deviceID else { return }
        loadedForDeviceID = deviceID
        loading = true
        Task {
            defer { self.loading = false }
            // Concurrently: four independent reads, and a settings screen that
            // opens in four sequential round trips feels broken.
            // No input read here: it arrives from the transport poll, which is
            // both live and already happening. See `inputObserver`.
            //
            // `attempt` rather than `try?` because the two nils are different
            // answers: "the device says no value" is settled and must not be
            // retried forever, while "the request never landed" is a gap that
            // draws an empty screen and used to persist until the device was
            // switched away from and back.
            async let identity = plugin.identify()
            async let output = Self.attempt { try await plugin.audioOutput() }
            async let channel = Self.attempt { try await plugin.channelMode() }
            async let profiles = Self.attempt { try await plugin.roomFitProfiles() }
            async let correction = Self.attempt { try await plugin.roomFitState(source: .default) }

            let resolved = await identity
            let (outputValue, outputFailed) = await output
            let (channelValue, channelFailed) = await channel
            let (profilesValue, profilesFailed) = await profiles
            let (correctionValue, correctionFailed) = await correction

            self.identity = resolved
            self.output = outputValue
            self.channelMode = channelValue
            self.roomFitProfiles = profilesValue ?? []
            self.roomFit = correctionValue

            let anyFailed = outputFailed || channelFailed || profilesFailed || correctionFailed

            // A device that didn't name itself isn't loaded, so don't record it
            // as such. Every capability table is keyed on the model, so without
            // one there is nothing honest to draw — and with the guard left set,
            // the only way back was to select another device and return, which
            // changes the ID and forces the reload. That's precisely the bug
            // this clears: the first open of Controls after launch could sit on
            // an unusable screen indefinitely.
            //
            // A failed *read* clears it for the same reason — the screen is
            // drawing a blank where a value belongs, and nothing else will ever
            // ask again. A read that succeeded and returned nothing does not:
            // that is a settled answer, and retrying it forever would poll the
            // device on a loop for a value it has already given.
            if resolved == nil || anyFailed { self.loadedForDeviceID = nil }

            // The screen is already open and already wrong, so waiting for the
            // next visit is too late. One retry only — `retrying` stops a device
            // that fails consistently from turning this into a poll loop.
            if anyFailed && !self.retrying {
                self.retrying = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    self.retrying = false
                    guard DeviceController.shared.currentPlugin?.device.id == deviceID else { return }
                    self.loadIfNeeded(force: true)
                }
            }
        }
    }

    /// Guards the single automatic retry, so a device failing every read can't
    /// drive `loadIfNeeded` in a loop.
    private var retrying = false

    /// Runs a read, keeping *why* the result is missing.
    ///
    /// Returns `(nil, true)` when the request threw and `(nil, false)` when it
    /// answered with no value. `try?` collapses those, which is what let a
    /// dropped request draw an empty control that never refilled.
    private static func attempt<T>(
        _ work: @Sendable () async throws -> T?
    ) async -> (T?, Bool) {
        do {
            return (try await work(), false)
        } catch {
            return (nil, true)
        }
    }

    /// The device's current volume, so a preset that sets one can start from
    /// where the user already is rather than an arbitrary number.
    var currentVolume: Int? { DeviceController.shared.status?.volume }


    /// How far one press of a volume key or arrow moves the level, **per
    /// device**. A step that suits desktop speakers is wrong for an amplifier
    /// driving a room, and larc points at both from the same menu.
    ///
    /// Never disabled by the media-keys setting: the popover's own arrow keys
    /// use it too, and those work whether or not the keys are being captured
    /// system-wide.
    var volumeStep: Int {
        get { VolumeStepStore.step(for: DeviceController.shared.selectedID) }
        set {
            objectWillChange.send()
            VolumeStepStore.setStep(newValue, for: DeviceController.shared.selectedID)
        }
    }

    /// Whether the device has said what it is yet.
    ///
    /// Output labels are per model, so before this is true the only honest
    /// answer is "not yet" — not a guess.
    var isIdentified: Bool { identity != nil }

    /// Whether the Controls screen has enough to draw.
    ///
    /// The same condition as `isIdentified` today, named separately because
    /// it's asked for a different reason: one is "do we know the model", the
    /// other is "is it worth opening the screen". If a future setting has its
    /// own precondition, this is where it goes.
    var isReadyForControls: Bool { isIdentified }

    /// Empty until the device is identified.
    ///
    /// `AudioOutput.known(nil)` returns 1…6 unlabelled, which is right for
    /// hardware we can't name but wrong for hardware we simply haven't asked
    /// yet. Rendering it meant the Controls screen showed bare numbers for a
    /// moment and then swapped them for real names — a flash that read as a
    /// glitch. A screen should show nothing rather than something it's about to
    /// contradict.
    var availableOutputs: [AudioOutput] {
        guard let identity else { return [] }
        return AudioOutput.known(for: identity.model)
    }

    /// "None" plus every stored profile — the picker's full list, with None
    /// first so its position doesn't move as profiles come and go.
    var roomFitOptions: [RoomFitSelection] {
        [.off] + roomFitProfiles.map(RoomFitSelection.profile)
    }

    var currentRoomFitSelection: RoomFitSelection {
        roomFit?.selection(among: roomFitProfiles) ?? .off
    }

    // MARK: - Changes

    func setInput(_ value: AudioInput) {
        apply(pending: .input(value),
              optimistic: { self.input = value }, revert: { [previous = input] in
            self.input = previous
        }, work: { try await $0.setInput(value) },
        failure: "\(value.displayName) isn't available on this device.")
    }

    func setOutput(_ value: AudioOutput) {
        apply(pending: .output(value.rawValue),
              optimistic: { self.output = value }, revert: { [previous = output] in
            self.output = previous
        }, work: { try await $0.setAudioOutput(value) },
        // Not "refused" outright: the tile stays, marked with a caution, and
        // stays selectable. See AudioOutput.known(for:).
        failure: "\(value.displayName) didn't take. It's still worth a try.")
    }

    func setChannelMode(_ value: ChannelMode) {
        apply(pending: .channel(value.rawValue),
              optimistic: { self.channelMode = value }, revert: { [previous = channelMode] in
            self.channelMode = previous
        }, work: { try await $0.setChannelMode(value) },
        failure: "Couldn't change the channel mode.")
    }

    func setRoomFit(_ selection: RoomFitSelection) {
        let optimistic = RoomFitState(
            profileName: selection.channelMode == nil ? (roomFit?.profileName ?? "") : {
                if case .profile(let profile) = selection { return profile.name }
                return roomFit?.profileName ?? ""
            }(),
            enabled: selection != .off,
            channelMode: selection.channelMode ?? roomFit?.channelMode ?? "Stereo"
        )
        apply(pending: .roomFit,
              optimistic: { self.roomFit = optimistic }, revert: { [previous = roomFit] in
            self.roomFit = previous
        }, work: { try await $0.setRoomFit(selection) },
        failure: "Couldn't change room correction.")
    }

    /// Optimistic update, then verify, then revert on failure.
    ///
    /// Written once rather than four times because getting it subtly different
    /// per setting is how a UI ends up trusting `OK` in one place and not
    /// another — which is exactly the bug this hardware invites.
    private func apply(
        pending change: PendingChange,
        optimistic: @escaping () -> Void,
        revert: @escaping () -> Void,
        work: @escaping (LinkplayPlugin) async throws -> Void,
        failure: String
    ) {
        guard let plugin else { return }
        lastError = nil
        optimistic()

        let token = UUID()
        inFlight = token
        pending = nil
        // Separate task, so the delay never holds up the request itself.
        Task {
            try? await Task.sleep(for: .seconds(Self.breathAfter))
            guard self.inFlight == token else { return }
            self.pending = change
        }

        Task {
            defer {
                if self.inFlight == token {
                    self.inFlight = nil
                    self.pending = nil
                }
            }
            do {
                try await work(plugin)
            } catch {
                revert()
                lastError = failure
                // Then ask the device what's actually true, rather than leaving
                // the remembered value on screen.
                //
                // `revert` restores what we had *before* the attempt, which is
                // only right if the write did nothing. A write that succeeded
                // but failed to confirm leaves the two disagreeing — the device
                // on its new setting, the popover insisting on the old one —
                // and that is worse than either being briefly wrong, because
                // nothing later corrects it.
                loadIfNeeded(force: true)
            }
        }
    }

    // MARK: - Presets

    /// Applies a preset, touching only the settings it defines.
    ///
    /// Sequential rather than concurrent: switching input can change what the
    /// other settings apply to, so the order is input → output → channel →
    /// correction → volume, and each waits for the last.
    func apply(_ preset: Preset) {
        guard let plugin else { return }
        lastError = nil
        Task {
            if let input = preset.input {
                try? await plugin.setInput(input)
                self.input = try? await plugin.currentInput()
            }
            // Resolved against *this* device's model, and skipped outright if
            // it names an output this one hasn't got. The alternative — sending
            // the number the preset was built with — routes to whichever jack
            // that number happens to mean here, which is how a preset made on an
            // Ultra used to send an Amp's audio to its speaker terminals.
            if let value = preset.outputValue(on: identity?.model) {
                let output = AudioOutput(value, model: identity?.model)
                try? await plugin.setAudioOutput(output)
                self.output = try? await plugin.audioOutput()
            }
            if let value = preset.channelModeValue {
                try? await plugin.setChannelMode(ChannelMode(value))
                self.channelMode = try? await plugin.channelMode()
            }
            switch preset.roomFit {
            case .unchanged: break
            case .off:
                try? await plugin.setRoomFit(.off)
            case .profile(let name):
                if let match = roomFitProfiles.first(where: { $0.name == name }) {
                    try? await plugin.setRoomFit(.profile(match))
                }
            }
            if preset.roomFit != .unchanged {
                self.roomFit = try? await plugin.roomFitState(source: .default)
            }
            if let volume = preset.volume {
                DeviceController.shared.userSetVolume(Double(volume))
            }
        }
    }
}
