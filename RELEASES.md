# Releases

## 1.7.0 — 2026-08-07

First public release.

- An app icon.
- Media keys are decided per key: volume always reaches the streamer, play and
  skip go to the Mac on line-in, optical and phono, and every key goes to the
  Mac when the streamer isn't answering.
- The input shown in Controls follows the device, including when the device
  changes it on its own.
- Stopping playback no longer clears the selected input.
- Inputs larc doesn't recognise are treated as network rather than as nothing.

## 1.6.0 — 2026-07-30

- Fallback album art: the larc logo when a cover isn't available.
- The logo dims while nothing is playing.
- Track controls hidden on line-in, optical and phono.
- The artwork tuning window is dev-only from here.

## 1.5.0 — 2026-07-30

- Album art sampled at 16×16 and sorted into nine brightness/contrast categories.
- Exposure, contrast, saturation, vibrance and layer opacity, set per category.
- A tuning window with live previews, dev builds only.

## 1.4.0 — 2026-07-29

- Controls screen: input, output, channel mode and room correction.
- RoomFit profiles: list, select, disable.
- Presets: input, output, channel mode, correction profile and volume in one click.
- Preset editor with an icon and colour picker.
- The popover becomes a navigation stack.
- One shared design system across pills, tiles and circles.
- `./build.sh --fast`, and a `--dev` component gallery.

## 1.3.2 — 2026-07-26

- Both marquee lines run off one clock, and stop when playback stops.
- Play state survives a track change.

## 1.3.1 — 2026-07-26

- Album art from LAN hosts using self-signed certificates.
- Public `http` artwork URLs upgraded to `https`.
- Station name shown when artist and album are empty.

## 1.3.0 — 2026-07-26

- The popover takes its colour from the album art.
- A full-bleed artwork watermark behind the controls.
- Separate light and dark treatments.

## 1.2.0 — 2026-07-26

- A steady play/pause glyph across track changes.
- Volume and play state held across a device switch.

## 1.1.0 — 2026-07-26

- Title, artist and album from the device.
- Album art.
- Track text scrolls when it doesn't fit.
- Popover narrowed to 240pt.

## 1.0.0 — 2026-07-26

First stable release.

- Native popover behaviour: Esc, outside-click and app-switch all dismiss.
- The volume slider is always visible.
- Focus rings appear only when asked for.
- Hotkey hint badges on `?` and Tab.
- Liquid Glass on macOS 26, still running on macOS 14.

## Before 1.0.0

The foundation.

- WiiM/Linkplay control over the local network: volume, mute, transport.
- Device discovery over mDNS, remembered per network.
- Menu bar item with a speaker glyph and a numeric volume flash.
- Media keys, system-wide.
- Global Cmd+Ctrl+L, plus hotkeys inside the popover.
- First-run onboarding.
- A `DevicePlugin` protocol, so other backends can be added.
