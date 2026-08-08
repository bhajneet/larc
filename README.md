# Larc is a Local Audio Remote Controller — menu bar volume & media keys for WiiM (macOS)

Larc lives in your Mac's menu bar and controls network audio streamers on your
local network. Point your keyboard's volume and media keys at your WiiM (or
other Linkplay-based) streamer instead of the Mac itself — no cloud, no
accounts, everything stays on your LAN.

## Features

- 🎚 Menu bar popover: volume slider, mute, play/pause, next/previous, current track — plus all settings (media keys, volume step, launch at login, rescan)
- ⌨️ Media key capture: one toggle sends all six media keys (volume up/down/mute, play/pause, next, previous) to the streamer instead of the Mac
- 🔎 Automatic discovery of WiiM/Linkplay devices via Bonjour (`_linkplay._tcp`)
- 🔐 Talks to the device over HTTPS (accepting only that device's self-signed certificate), falling back to HTTP for older firmware
- 🚀 Launch at Login, configurable volume step
- Zero third-party dependencies

## Requirements

- macOS 14 Sonoma or later (Universal: Apple Silicon + Intel)
- A WiiM or other Linkplay-based streamer on the same network

## Install

### Download

Grab the latest `Larc-x.y.z.dmg` from
[Releases](https://github.com/bhajneet/larc/releases), open it, and drag
`Larc.app` onto the `Applications` shortcut. A speaker icon appears in the
menu bar.

**macOS will refuse to open it the first time.** Larc is not signed with an
Apple Developer ID that costs $99/year, and this is a free app with no
revenue behind it.

To open it anyway:

1. Double-click `Larc.app`. macOS refuses. Dismiss the dialog.
2. Open **System Settings → Privacy & Security**, scroll down, and click
   **Open Anyway** next to the message about Larc.
3. Confirm. This is needed once, not on every launch.

macOS 15 removed the older right-click → Open shortcut, so the Settings route
above is the one that works. If you prefer the terminal:

```bash
xattr -d com.apple.quarantine /Applications/Larc.app
```

### Or build it yourself

Building from source avoids all of the above — locally built apps are never
quarantined, so nothing blocks them.

```bash
git clone https://github.com/bhajneet/larc.git
cd larc
./build.sh          # → build/Larc.app
```

Requires the Xcode command line tools. `xcodebuild -project larc.xcodeproj
-scheme larc -configuration Release` also works if you prefer Xcode's build
system.

### First run

Larc walks you through a short onboarding: what the app does, finding devices
on your local network (macOS 15+ will ask for Local Network access — required;
without it Larc cannot discover any device), picking your active device, and
optionally enabling media key capture.

### Accessibility permission (required for media keys)

Larc uses an event tap to capture media keys, which macOS gates behind
Accessibility access. Onboarding offers to request it; you can also enable it
any time via the Media Keys toggle in the menu bar popover, or manually in
System Settings → Privacy & Security → Accessibility → **Larc**. The Media
Keys toggle is only ever on when capture actually works. Without this
permission everything works except media key capture.

**Developers:** an ad-hoc signature ties the Accessibility grant to the exact
binary, so every rebuild silently invalidates it — System Settings still shows
Larc enabled, but the check fails until you run
`tccutil reset Accessibility com.studioaiyo.larc` and grant again. To avoid
this, create a self-signed code-signing certificate named `larc-dev` (Keychain
Access → Certificate Assistant → Create a Certificate… → Identity Type:
Self-Signed Root, Certificate Type: Code Signing); `build.sh` picks it up
automatically and the grant then survives rebuilds.

## Releases

Version history is in [RELEASES.md](RELEASES.md).

## Roadmap

Planned device plugins (verified protocol facts):

| Backend | Protocol | Discovery |
|---|---|---|
| **BluOS** (Bluesound, NAD) | HTTP/XML on port 11000 | mDNS `_musc._tcp` / `_musp._tcp` |
| **Yamaha MusicCast** | Yamaha Extended Control, JSON on port 80 | SSDP MediaRenderer |
| **Denon/Marantz HEOS** | persistent TCP ASCII/JSON on port 1255 | SSDP ST `urn:schemas-denon-com:device:ACT-Denon:1` |

Also planned: Sparkle auto-updates, signed/notarized releases.
