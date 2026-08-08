# Roadmap

What's agreed but not built, grouped by when. **CLAUDE.md records decisions and
their reasons; this records intentions.** Anything here that gets built moves to
CLAUDE.md with its reasoning and comes off this list.

## Next tag (1.6.0)

Agreed, will definitely happen. None of these made 1.5.0, which turned out
to be the artwork pipeline instead.

- **URL field in Controls**, above Input. Paste a stream URL and play it via
  `setPlayerCmd:play:<url>` — the same command the vendor app uses for
  everything it plays. Then a preset can carry one, making a preset a bookmark
  that also sets input, output and volume.
- **Volume step read from the device.** The vendor app has a "knob volume step"
  with values 1–5. If that's readable and writable, larc should use it rather
  than keeping its own — which would leave media keys and Launch at Login as
  the only settings that are larc's own. Needs the command found first; nothing
  in the enumeration matched, so this likely needs a
  `--mode local:MuzoHome` capture with that screen open.
- **Queue — confirmed rich, and the next real feature.** `enumerate-upnp.py` on
  the Ultra listed `urn:schemas-wiimu-com:service:PlayQueue:1`, which supports
  everything a queue screen needs:
    - `BrowseQueueEx(QueueName, TrackIndex, TrackNums)` — paged read
    - `GetQueueIndex` — current index, preloading index, page, track count
    - `PlayQueueWithIndex` — jump to track N
    - `RemoveTracksInQueue(RangStart, RangEnd, Action)`
    - `MoveTracksInQueue(IndexList, ToIndex)` — reorder
    - `DeleteQueue`, `ReplaceQueue`, `AppendTracksInQueueEx`
    - `SetQueueLoopMode` / `GetQueueLoopMode` — **where shuffle most likely
      lives.** `getPlayerStatus` already returns a `loop` field, so the values
      can be mapped by setting each and reading it back.
  Also on `AVTransport`: `Seek(Unit, Target)`, a standard second seek path, and
  `GetInfoEx` which returns transport state, position, volume, mute, channel and
  battery in one call.

  **The cost is a SOAP client**, which larc doesn't have — everything today is
  `GET httpapi.asp`. This needs POST with a SOAP envelope and DIDL-Lite XML
  parsing out of `QueueContext`. ~150 lines and its own commit; the screen is
  the easy half. `QueueScreen` is a mock until then and says so on screen.

## Later

- **`EQv2SourceLoad` / `EQChangeSourceFX`.** Names only, from the vendor app's
  Firebase crash telemetry; never called successfully. Guessing payloads is what
  wasted 380 attempts before — the way in is another local-mode capture with the
  app's EQ screens open.
- **Per-band EQ.** `EQGetBand` reads all ten bands and the firmware runs the
  CAPS `Eq10HP` plugin, so there is a real parametric engine. Writing is
  unexplored.
- **`setMaxVolume`.** Confirmed working. A user-facing volume cap.
- **`plm_support` bits** beyond bit 16 (phono). One bit identified; don't guess
  the rest — a wrong map offers inputs the device lacks.
- **Amp channel-mode mapping** unverified by ear.
- **`POST /autoEQ/getConfig`** — cloud-side, unexplored, presumably part of
  RoomFit calibration.
- **`iconSingle` / `iconDouble`** are both 14 "on trial". Either they collapse
  into one name or they don't.

## Shipping — the next block of work

None of this is a feature. It is identity, packaging and trust, and it is what
stands between the app as it is and an app someone else can run.

**No Apple Developer account for now.** $99/year, and Organization enrollment
would need Studio Aiyo to be a registered legal entity — Apple rejects trade
names and sole proprietorships. Deferred until there's evidence anyone wants
the app. That decision sets everything below: releases are ad-hoc signed,
distributed from GitHub, and carry a Gatekeeper warning on first open.

### First release, from GitHub

- [ ] **Publish the repo.** No remote exists yet; the clone URL in the README
      points at nothing.
- [x] **App icon (`.icns`).** `./make-icon.sh [source.png]` shapes any square
      PNG to Apple's grid and writes `larc/Resources/Larc.icns`; `Info.plist`
      names it. Currently generated from `larc-logo.png`, which has no alpha,
      so the icon is a rounded tile of the cream artwork rather than a shape.
      Re-run with a transparent source if that should change.
- [ ] **Drop the `dev` suffix** for `com.studioaiyo.larc`. Do it before anyone
      installs, since changing it later costs users their settings and grants.
- [ ] **Distribution artifact.** Zip or DMG from `./build.sh`, attached to a
      GitHub Release. Download counts come free with the Release.
- [ ] **Document the Gatekeeper bypass in the README.** Ad-hoc signed means
      macOS refuses the first open, and macOS 15 removed the old right-click →
      Open route. Users need System Settings → Privacy & Security → **Open
      Anyway**, or `xattr -d com.apple.quarantine`. Building from source has no
      such problem — locally built apps are never quarantined.
- [ ] **Test on a machine that has never seen the app** — the only way to find
      out what a real first launch does, including the Local Network prompt.
- [ ] **Post to the WiiM forums**, r/WiiM and AVS. Discovery is the actual
      constraint; nobody browses for a WiiM controller.

### If there's interest

- [ ] **Apple Developer Program**, $99/year. Individual enrollment is immediate
      and needs no D-U-N-S, but publishes the maintainer's legal name.
      Organization needs Studio Aiyo registered as an LLC first, then a free
      D-U-N-S via developer.apple.com/enroll/duns-lookup (~5 business days).
- [ ] **Hardened runtime.** `build.sh` signs with `codesign --force --deep
      --sign`; notarization *rejects* anything without `--options runtime`. Also
      review `--deep`, which Apple has deprecated for signing.
- [ ] **Notarize and staple.** `xcrun notarytool submit --wait` then `xcrun
      stapler staple`. Notarize the artifact, not just the app, or Gatekeeper
      still warns. Needs an app-specific password or an API key.
- [ ] **Donation ask.** Usage-gated, one-time, dismissible, after the app has
      proven useful. Needs `firstLaunchDate` plus distinct-weeks-active in
      UserDefaults, no telemetry. Platform open: GitHub Sponsors / Ko-fi.
- [ ] **Sparkle auto-updates**, last, since it wants a stable signing identity
      and a place to host an appcast.

Not blocking, but adjacent:

- **Real `xcodebuild` as the build path.** The Xcode project, scheme and product
  are still lowercase `larc`; only the app was rebranded `Larc`. `build.sh` has
  been the only build path for a long time and works — this is tidiness, and it
  can wait until something actually needs Xcode.
- **A second machine to test on.** Nothing about first launch — the Local
  Network prompt, onboarding, the Gatekeeper refusal — can be judged on the
  machine that built the app.

## Larc Keys split

Two free targets, sharing one codebase, split only where App Sandbox actually
blocks something. Full reasoning in CLAUDE.md — the short version is that a
*consuming* CGEventTap is the only thing that can't ship on the App Store, so
`MediaKeyTap` is the whole difference.

## Not planned

Recorded so they don't get re-proposed.

- **Clamping a slider to `max_volume`.** Tried and reverted. It is a *scaling*
  cap, not a range limit: set it to 50 on a WiiM and the device still reports
  and accepts 0–100, with 100 meaning whatever 50 used to. Clamping stopped larc
  reaching the top of a range the device was still offering.

- **Media keys while the popover is open, without Accessibility.** Tried and
  abandoned. Physical volume keys are handled below where a local monitor can
  see them; only a session-level CGEventTap can take them.
- **A hand-built volume slider** to hide the knob. ~80 lines, loses native
  behaviour, and the track has to stay visible to read the level.
- **Tinting the popover's arrow.** Drawn by AppKit's private `NSPopoverFrame`;
  the routes are private-frame surgery or a custom panel, both rejected.
- **Forcing overlay scrollers.** Three attempts, none reached the scroll view.
  The OS draws the scroller in the style the OS chose, and the header is inset
  to match.
