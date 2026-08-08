import SwiftUI

/// A saved bundle of device settings the user can apply in one click.
///
/// The point is that the vendor's app spreads input, output, channel mode and
/// room correction across four separate screens, so "switch to the turntable"
/// is a four-screen chore. A preset makes it one row.
///
/// **Every setting is optional, and nil means "leave it alone".** That's the
/// difference between a preset and a snapshot: a "Late night" preset can lower
/// the volume and switch room correction without touching whichever input you
/// happen to be listening to. Applying a preset should only ever change what it
/// explicitly says.
struct Preset: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    /// SF Symbol name.
    var symbol: String = "music.note"
    var tint: PresetTint = .blue

    var input: AudioInput?
    /// The output's **name** — "Line Out", "Optical" — resolved against
    /// whichever device the preset is applied to.
    ///
    /// **The number alone is not portable, and storing it was a silent bug.**
    /// The same value is a different jack per model: 2 is Line Out on a WiiM
    /// Ultra and the speaker terminals on a WiiM Amp. A comment here used to
    /// argue the number "keeps it honest — it either works on the hardware
    /// present or it fails the readback", which is exactly what doesn't happen
    /// when both models accept it: a "TV time" preset built on an Ultra applied
    /// to an Amp set output 2, the readback confirmed 2, and the audio went to
    /// the speakers. It succeeded at the wrong thing.
    ///
    /// A name resolves correctly or not at all. `AudioOutput` already keeps
    /// per-model label tables, so "Line Out" finds the right number on hardware
    /// that has one and finds nothing on hardware that doesn't — and a preset
    /// naming a jack this device lacks skips output rather than guessing.
    var outputLabel: String?
    /// The raw value, kept as a fallback for two cases a label can't serve:
    /// presets saved before labels existed, and hardware larc has no mapping
    /// for, where every "label" is just the number rendered as text.
    ///
    /// Only consulted when `outputLabel` is nil. A preset that names an output
    /// this device doesn't have must skip it, not fall back to a number that
    /// means something else here.
    var outputValue: Int?
    var channelModeValue: Int?
    var roomFit: PresetRoomFit = .unchanged
    /// 0–100. Deliberately uncapped: unlike an automated sweep, this is a value
    /// the user typed for their own system, and a preset that can't reach the
    /// level they want is useless.
    var volume: Int?

    /// Whether this preset sets an output at all, by either route.
    var setsOutput: Bool { outputLabel != nil || outputValue != nil }

    /// The value to send on a given model, or nil if this preset's output isn't
    /// available there.
    ///
    /// Nil is a real answer, not a failure: a preset naming "Line Out" applied
    /// to an amplifier that has only speaker terminals should leave the output
    /// alone. Skipping is the honest outcome — the preset asked for something
    /// this hardware hasn't got.
    func outputValue(on model: String?) -> Int? {
        guard let outputLabel else { return outputValue }
        return AudioOutput.known(for: model)
            .first { $0.displayName == outputLabel }?
            .rawValue
    }

    /// True when this preset names an output the given model doesn't have — so
    /// a row can say the preset won't fully apply here rather than quietly
    /// doing less than it says.
    func outputUnavailable(on model: String?) -> Bool {
        outputLabel != nil && outputValue(on: model) == nil
    }

    /// What the row should say underneath the name — a short summary of what
    /// applying it will actually do **on this device**, so the list is readable
    /// without opening each one.
    ///
    /// Takes the model rather than a closure to resolve output names: it needed
    /// the model anyway, and passing it directly is what lets the summary say
    /// when a preset won't fully apply here.
    func summary(on model: String?) -> String {
        var parts: [String] = []
        if let input { parts.append(input.displayName) }
        // The stored name where there is one, since that's what the user chose
        // and it reads the same on every device — marked when this particular
        // device hasn't got it, so a preset that will quietly skip its output
        // says so before you press it rather than after.
        if let outputLabel {
            parts.append(outputUnavailable(on: model)
                         ? "\(outputLabel) (not here)" : outputLabel)
        } else if let outputValue {
            parts.append(AudioOutput(outputValue, model: model).shortName)
        }
        if let channelModeValue, channelModeValue != 0 {
            parts.append(ChannelMode(channelModeValue).shortName)
        }
        switch roomFit {
        case .unchanged: break
        case .off: parts.append("No correction")
        case .profile(let name): parts.append(name)
        }
        if let volume { parts.append("Vol \(volume)") }
        return parts.isEmpty ? "Nothing set yet" : parts.joined(separator: " · ")
    }

    var isEmpty: Bool {
        input == nil && !setsOutput && channelModeValue == nil
            && volume == nil && roomFit == .unchanged
    }
}

/// Room correction has three states in a preset, not two: leave it alone, turn
/// it off, or select a named profile. "Off" has to be expressible separately
/// from "unchanged" or a preset could never disable correction.
enum PresetRoomFit: Codable, Equatable, Hashable {
    case unchanged
    case off
    case profile(String)

    var label: String {
        switch self {
        case .unchanged: return "Don't change"
        case .off: return "None"
        case .profile(let name): return name
        }
    }
}

/// The tint palette, mirroring the colours Apple offers when customising a
/// Focus or a Messages group. Stored by name rather than as a `Color` so it
/// survives encoding and follows the system's light/dark rendering.
enum PresetTint: String, Codable, CaseIterable, Identifiable, Hashable {
    case blue, brown, gray, green, indigo, orange, pink, purple
    case red, teal, yellow, mint

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .brown: return .brown
        case .gray: return .gray
        case .green: return .green
        case .indigo: return .indigo
        case .orange: return .orange
        case .pink: return .pink
        case .purple: return .purple
        case .red: return .red
        case .teal: return .teal
        case .yellow: return .yellow
        case .mint: return .mint
        }
    }
}

/// Symbols offered when customising a preset.
///
/// Curated rather than all of SF Symbols: a search field plus a scrolling grid
/// of six thousand mostly-irrelevant glyphs doesn't fit a 240pt popover, and
/// the useful set for "what am I listening to" is small. Grouped loosely by
/// what a preset tends to be about — a room, a source, a mood, a time of day.
enum PresetSymbols {
    static let all: [String] = [
        // sources
        "music.note", "hifispeaker.fill", "headphones", "tv", "gamecontroller.fill",
        "opticaldisc.fill", "radio.fill", "guitars.fill", "pianokeys", "mic.fill",
        // rooms
        "sofa.fill", "bed.double.fill", "fork.knife", "desktopcomputer",
        "house.fill", "building.columns.fill", "books.vertical.fill", "shower.fill",
        // moods and times
        "moon.fill", "sun.max.fill", "sunrise.fill", "sunset.fill",
        "party.popper.fill", "figure.run", "brain.head.profile", "leaf.fill",
        // audio-ish
        "waveform", "speaker.wave.3.fill", "dial.medium.fill", "slider.horizontal.3",
        "ear.fill", "volume.3.fill", "airpodspro", "beats.headphones",
        // generic
        "star.fill", "heart.fill", "bolt.fill", "flame.fill",
        "bookmark.fill", "tag.fill", "flag.fill", "sparkles",
    ]
}

/// Presets, persisted as JSON in `UserDefaults`.
///
/// A plain `ObservableObject` rather than `@AppStorage`: the list is an array of
/// structs that several screens edit, and `@AppStorage` would re-encode the
/// whole array on every keystroke while renaming.
@MainActor
final class PresetStore: ObservableObject {
    static let shared = PresetStore()

    @Published private(set) var presets: [Preset] = []

    private let key = "larcPresets"

    init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Preset].self, from: data)
        else { return }
        presets = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    @discardableResult
    func add() -> Preset {
        // Numbered so a run of new presets doesn't produce several rows that
        // read identically before they're configured.
        let preset = Preset(name: unusedDefaultName())
        presets.append(preset)
        save()
        return preset
    }

    /// "Preset 1", "Preset 2", … skipping any number already taken.
    ///
    /// **Was `presets.count + 1`, which repeats as soon as anything is
    /// deleted.** With Preset 1 and Preset 2, removing the first leaves a count
    /// of one, so the next new preset is called Preset 2 as well — two rows with
    /// the same name and different settings, and nothing on screen to tell them
    /// apart. Counting what exists says nothing about what's free.
    private func unusedDefaultName() -> String {
        let taken = Set(presets.map(\.name))
        var n = 1
        while taken.contains("\(PopoverScreen.presetNoun) \(n)") { n += 1 }
        return "\(PopoverScreen.presetNoun) \(n)"
    }

    /// Whether another preset already answers to this name.
    ///
    /// **Reported, never corrected.** An earlier version appended a number when
    /// a name collided, which produced "Preset 2 2" — a name nobody typed, that
    /// looks like a bug, and that quietly accepted an edit the user would have
    /// changed had they known. Renaming someone's text on their behalf is worse
    /// than refusing it.
    ///
    /// Case- and whitespace-insensitive: two presets differing only in a
    /// trailing space or a capital are the same name to anyone reading the list.
    func nameIsTaken(_ name: String, excluding id: UUID) -> Bool {
        let candidate = Self.comparable(name)
        guard !candidate.isEmpty else { return false }
        return presets.contains {
            $0.id != id && Self.comparable($0.name) == candidate
        }
    }

    private static func comparable(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Restores a name, for abandoning an edit that was never valid.
    func rename(id: UUID, to name: String) {
        guard let index = presets.firstIndex(where: { $0.id == id }),
              presets[index].name != name else { return }
        presets[index].name = name
        save()
    }

    func update(_ preset: Preset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index] = preset
        save()
    }

    #if LARC_DEV
    /// Clears every preset. **`--dev` only**, and deliberately so: this is for
    /// resetting after a session of test presets, not a feature. A real "delete
    /// all" would need a confirmation, and there is no undo here.
    func deleteAll() {
        presets.removeAll()
        save()
    }
    #endif

    func delete(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        save()
    }

    func preset(id: UUID) -> Preset? {
        presets.first { $0.id == id }
    }
}
