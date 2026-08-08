# Larc — Local Audio Remote Controller

macOS menu bar app controlling network audio streamers locally. First backend: WiiM/Linkplay. Open source, MIT. Clean-room: no code/assets from any existing app. Logo (songbird lark) developed separately by the maintainer.

**How to read this file.** It records *decisions and the reasons for them*, not a changelog. Where something says "don't do X", X has been tried and cost real time. Prune anything that has stopped guiding a decision.

## Constraints

- Never touch anything outside the project dir.
- Ask before sudo, non-local network, or system settings changes.
- Prefer zero third-party dependencies.
- Captures (`*.mitm`) contain the maintainer's **Plex token** — gitignored, scrub before sharing.
- Claude cannot edit `.claude/settings*.json`; hand permission changes to the maintainer as a list.

## Environment

- macOS 26.5.2, Xcode 26.6, Swift 6.3.3, arm64 host. Target macOS 14+, Universal (arm64 + x86_64).
- `swift`/`xcodebuild` print a harmless `couldn't create cache file … xcrun_db` under the sandbox — ignore.
- **`tccutil reset All <bundle-id>` froze the maintainer's whole machine twice** (mouse dead, blind `sudo reboot` required). Never suggest it. Single-service resets are fine (`tccutil reset Accessibility …`); no working service string for Local Network was ever found.
- **The `!`-prefixed "run in this session" shell is also sandboxed** — it is not an escape hatch. Anything needing real system access (`tccutil`, keychain trust) must be run by the maintainer in a real Terminal.

## Build commands

**Claude runs `./check.sh`. The maintainer runs `./build.sh`.** Not optional — see below.

```bash
./check.sh                    # type-check only, ~3s. No bundle, no signature. Always -D LARC_DEV.
./build.sh                    # -O, both arches, bundle + sign → build/Larc.app. ~25s.
./build.sh --fast             # -Onone, arm64 only. ~6s. Same signing, so TCC grants survive.
./build.sh --dev              # compiles the Dev component gallery in (-D LARC_DEV).
```

- `--fast` is for looking, not keeping: no Intel slice, unoptimized. Use a plain build before judging animation smoothness or handing the app to anyone.
- `-enable-batch-mode` would take the compile to ~1s across cores, but its per-file objects go missing before the link with no compile error. Not shipped; symptom recorded in `build.sh` if worth chasing.
- Mock devices: `open build/Larc.app --args --mock-devices N`.

### Rebuilding revokes permissions

`./build.sh` **inside the Claude sandbox always ad-hoc signs** — `security find-identity -v -p codesigning` reports 0 identities there, so the `larc-dev` fallback can never trigger. Ad-hoc signatures get a fresh cdhash per build, and macOS keys TCC grants (**Local Network and Accessibility both**) to the cdhash. Every Claude rebuild therefore silently revokes whatever the maintainer granted.

This is what broke Local Network on 2026-07-26: ~15 rebuilds in one session, after which the permission could not be made to stick.

- Verify with `codesign -dv build/Larc.app 2>&1 | grep Authority`. `(unavailable)` means ad-hoc and grants will not survive.
- The `larc-dev` cert is a self-signed root, Code Signing type, **and its Trust setting must be "Always Trust"** or `security find-identity` won't count it valid.

### When TCC state seems unfixable: bump the bundle ID

macOS keys local-network records to the **bundle ID**. Enough ad-hoc builds under one ID leaves a record it can't reconcile: the prompt appears, the maintainer accepts, nothing changes; System Settings toggling, rebooting and re-signing all fail.

**Fix: build under a throwaway ID** (`com.studioaiyo.larc.dev2`, `dev3`, … in `build.sh`, `larc.xcodeproj` and `tools/start.sh`). macOS treats a never-before-seen ID as a new app and prompts cleanly. Cost: UserDefaults and all grants are abandoned, so onboarding re-runs. Cheap. **Reach for this before another round of resets** — every alternative was tried and none worked.

**`com.studioaiyo.larc` is the ship ID and is now frozen.** It has shipped to users, whose settings and permissions are keyed to it. Burn `.devN` suffixes locally instead, and never release under one.

## Git setup (sandbox)

The sandbox hard-denies every write to a path named `.git`, and this is **not fixable via settings** (`allowWrite` loses to a built-in deny; there is no write-side re-allow key). Don't try again.

The real git dir is **`.gitdir/`**, with `.git` as a one-line pointer file `gitdir: .gitdir` — git's standard indirection, so the maintainer's plain `git`/IDE works normally. `.gitdir/` needs an explicit `.gitignore` rule.

**Tools that look for a `.git` directory rather than asking git will not see this repo.** `gh repo create --source=.` reports "current directory is not a git repository" even though `git rev-parse --git-dir` resolves fine. Work around it by not asking such a tool to detect the repo — create the remote without `--source`, then `git remote add origin …` and `git push -u origin main`, which are plain git and work normally.

---

# Design system

Everything visual lives in `larc/Presets/Components.swift` (`LarcUI` + the components) and `Metrics` in `larc/PopoverView.swift`. **Nothing re-implements a look locally.** That rule exists because it was broken: three row styles each grew their own hover fill and drifted apart.

## Type: three sizes

| token | size | used by |
|---|---|---|
| `headerFont` | 14 semibold | a sub-screen's own name |
| `rowFont` | 12 | **every title** — row, setting row, pill |
| `subtitleFont` | 9 | everything subordinate to a title |

There were seven. `pillTitleFont` (10) made the same word smaller in a capsule than in a row. `pillSubtitleFont` and `tileCaptionFont` (both 8) were a second secondary size. `sectionLabelFont` and `valueFont` were `subtitleFont` with a weight and a digit setting attached — modifiers at the call site, not sizes.

**Vary weight and digit spacing freely; don't add a size.** Section captions are `subtitleFont.weight(.semibold)`, the volume readout `.monospacedDigit()`.

## The grid

`Metrics` (popover geometry) and `LarcUI` (component geometry):

- `popoverWidth` **240**, `contentMargin` **15**, so `contentWidth` = **210**.
- `gridSpacing` **6**. The pair was chosen together: 210 with a 6pt gap divides into four 48pt pills and three 66pt tiles exactly, and 48 halves and quarters cleanly (a capsule's radius, a pill's leading inset). At margin 14 the unit is 47, whose quarter is 11.75.
- `backgroundPadding` **6** — how far a *background* reaches past the content it backs, applied as negative padding. Only three things use it: a row's hover fill, the accessibility warning, `MarqueeText.fade`.
- **Every control is a pill; a circle is a 1×1 one.** `pillSingle` 48 → `pillDouble` (2 units *plus the gap it swallows*) → `pillQuad`. `pillHeight` = `pillSingle`, so a row of mixed pills and circles shares one baseline. `tileHeight` = `pillHeight`, `presetTile` = half.
- `tileColumns` **4**, so a tile is exactly `pillSingle` and a tile grid sits on the same columns as a row of circles. At 3 the tile was 66 — a width nothing else shared.
- `iconSingle` and `iconDouble` are **both 14, on trial**: if one size reads right everywhere, they collapse to one. `iconColumn` **24** is stated, not derived — it was `iconDouble + slack` and moved whenever an icon size was tuned.
- **Icon size is a font size, not a width.** SF Symbols are glyphs. Sizing by width was tried: a chevron is ~1:2 so 14 wide rendered 28 tall, while `hifispeaker.2` at 2:1 shrank to ~7. Alignment comes from the *box*, not the glyph.

## Controls

**`LarcControl` owns everything a pill, tile and circle do identically** — the fill, the disabled opacity, the button, hover tracking, the press counter. A control supplies a shape and its contents; nothing else. Before it, the three were separate structs agreeing only by convention, with five copies of the same state, and they had already drifted (`LarcTile` took `isEnabled` where the others took `disabled`).

`LarcRow` deliberately keeps its own button: its highlight *bleeds* past its content by `backgroundPadding`, which is the one thing a control surface must not do. It publishes the same glyph motion.

- **Selected = accent fill, white mark.** The inverse of what it was. A white fill with an accent glyph reads as *lit* rather than chosen, and it leaned on a 2pt ring to be legible at all. Foreground is literal `Color.white`, not `.primary` — it sits on the accent, not the window, so it must not flip with the appearance.
- **No selection rings.** There were five; four duplicated a fill change that already said it. **The one that stays** is on the icon picker's colour swatches, where the fill *is* the value being chosen and a ring is the only mark available — neutral, held 3pt off the swatch so it reads against all six tints.
- **Fill changes fade** via `.animation(.default, value: fill)`, keyed to the resolved colour rather than to `selected` and `hovering` separately: `Color` is Equatable and `fill` encodes both, so one modifier covers hover, selection and release, and the foreground crosses with it. A hand-picked 0.15s duration was removed; the difference was never judged on screen.
- `cautionColor` (orange) vs `errorColor` (red): **the difference is whether you can carry on.** Orange marks what has already happened and can be ignored. Red is a state the UI won't let you leave. Sharing one colour would make neither mean anything.

## Glyph motion

Two gestures, both **SF Symbols' own effects** — nothing hand-animated.

- **Bounce** is feedback: `.symbolEffect(.bounce.up, value:)` on any press. `LarcCircleToggle` bounces **down** when the press switches it off (`isToggle`), so direction reads as starting versus stopping.
- **Breath** is state: `.breathe.plain` with `.repeat(.continuous)` while a control waits. macOS 15+; 14 falls back to `.pulse`.
- Controls and Scan pass `bouncesOnPress: false` — the breath starts the instant the press lands, so a bounce first only delays it and reads as two responses to one press.
- **Both bounce directions are attached permanently**, each watching its own counter. Swapping which modifier is applied changes view identity mid-animation, and deriving two counters from one shared number fires both at once.
- Motion reaches glyphs **through the environment** (`\.glyphBounce`, `\.glyphBreathing`), not as arguments — four components were threading the same two values through their content, and a glyph nested deeper couldn't reach it at all. A glyph outside any control reads the defaults and stays still.

## Sizing an `NSPopUpButton`-backed Picker

**`.fixedSize()` cannot hug a menu Picker's selection.** `NSPopUpButton`'s intrinsic width is that of its **widest menu item**: measured 189pt with either of two devices selected, against 145 for the shorter name alone. Against a 210pt content width that is indistinguishable from full width, and no frame modifier fixes a wrong intrinsic size.

`LarcUI.popUpWidth(for:)` states it instead — text plus `popUpChrome` **49**, measured constant at 48.2–48.6 across titles from one to thirty-four characters. The device picker sizes to the selected name (capped at `contentWidth`); the RC picker to its selected profile, capped at `settingControlMaxWidth` (`contentWidth * 0.75 - 2`).

## Sub-screen shell

- **All four gutters live *inside* the scroll view.** Outside they inset the *viewport*, so content clipped short of the popover's bottom edge with dead tint beneath it and short of the divider at the top. Inside, the viewport spans divider to popover edge and the gutter appears as breathing room at either end. The outer stack is `spacing: 0` so the header's gap can't reintroduce the top inset.
- `subScreenHeight` **starts at `subScreenMaxHeight`, not zero.** At zero the first layout pass gives the scroll view a zero-height frame and it settles on an offset computed in that state — a tall screen opened already scrolled.
- **Legacy scrollers steal width.** With "Show scroll bars: Always" the scroller is laid out beside the content, so the usable width is ~15pt less than the view. Content pinned to the full width is *wider than the area holding it*, and SwiftUI centres an oversized child — every scrolling screen sat half a scroller left of every non-scrolling one (7.5pt left margin against 22.5pt right). `Metrics.scrollerWidth` reads the real value from AppKit; zero under overlay scrollers.
- Scroll indicators are hidden while `navigation.isNavigating`, so a scroller never rides along with a sliding screen.

## Navigation

`PopoverNavigation` is a stack, not a Bool, so back works four levels deep. **Width is pinned at 240 on every screen** — a popover grows downward so height may change, but width shifts it sideways and `MarqueeText` measures against a fixed `popoverWidth`.

- **Root is always the main screen, in every build.** A `--dev` build used to land on the gallery; that was right while the gallery was the work and wrong the moment the app was.
- **Menu bar icon means "back" inside a sub-screen**, not close. Outside-click dismisses everything, and `popoverDidClose` resets to root.
- **Fixed transition edges**, not a direction flag: the main screen always enters and leaves left, a sub-screen always right. A direction flag was wrong half the time, because SwiftUI bakes a view's *removal* transition when the view is created.
- Transitions are keyed on the **whole stack** — pushing sub-screen → sub-screen changes neither the condition nor the view type, so SwiftUI reused the view with no animation.
- `popBlocked` stops going back when a screen holds something invalid (today: a duplicate preset name). **It never blocks closing** — the menu bar icon closes rather than going back while it's set. Held on the navigation object because three routes go back (button, Esc, menu bar icon) and a check in one is a check the other two skip. Also cleared in `reset()`, the one call that always runs on close, because a flag outliving its screen jams every later navigation.
- **The artwork tint is main-screen only.** It's sampled from what's playing; on Controls it was a colour with no referent on screen. Faded by opacity rather than removed conditionally, so it crosses with the slide.

---

# Architecture

- `DevicePlugin` protocol in `larc/Models.swift`; `LinkplayPlugin` (in `larc/Plugins/Linkplay/`) is the only implementation. New backends: implement the protocol, extend discovery, wire into `DeviceController`.
- `LinkplayDiscoverer` uses the raw `dnssd` C API (NWBrowser TXT access is awkward pre-13.4): browse → resolve → GetAddrInfo, one dispatch queue.
- `DeviceController` (@MainActor singleton) owns the device list, polling (2s popover open / 10s closed), volume coalescing (~150ms) and optimistic updates. Polls don't overwrite volume within 1.5s of a local change (slider-fight guard).
- Menu bar item is a manually-managed `NSStatusItem` + `NSPopover` in `AppDelegate`, **not `MenuBarExtra`** — which has no public API to toggle its popover from outside SwiftUI, which the global hotkey needs. `LarcApp.body` is just `Settings { EmptyView() }`.
- **The popover UI is 100% SwiftUI** — no representables anywhere. AppKit is confined to `NSStatusItem`/`NSPopover`, `CGEventTap`, Carbon hot keys, and `dnssd`. "Migrate the UI to SwiftUI" is not an available lever.
- `MediaKeyTap`: CGEventTap on NX_SYSDEFINED subtype 8. Needs Accessibility; app is deliberately **not** sandboxed, since consuming taps don't work in App Sandbox. Larc-Keys-only. `MediaKeyMapping` is factored out because the App Store target excludes the tap entirely.
- `GlobalHotKey`: Cmd+Ctrl+L via the Carbon Hot Key Manager. **The sandbox-safe way to claim a chord globally** — no TCC prompt at all. Carbon hot keys can't see NX_SYSDEFINED media keys, which is why capture still needs the separate tap. `build.sh` links `-framework Carbon` explicitly.
- `PopoverHotkeys`: a plain local `NSEvent` monitor, so no permission at all. It returns the event untouched when the first responder is a text field, or typing in the preset name field would trigger hotkeys.
- Mock devices, onboarding (`OnboardingView`, once via `hasCompletedOnboarding`), and `Relauncher` (`open -n`; newest instance kills older) are unchanged. Never `defaults delete` while larc runs — it strips the menu bar icon live into an invisible ghost; `tools/start.sh` kills first.

## Popover mechanics — settled, don't re-litigate

- **`togglePopover` reads `popover.isShown`. There is no tracked popover state.** Three previous attempts (Bool → generation-guarded Bool → 3-state enum) each fixed one desync and introduced another, because AppKit-initiated dismissal (Esc, deactivation, `.transient`) never went through our code. Do not reintroduce a phase enum.
- `behavior = .applicationDefined`, `animates` default. **This file said `.transient` long after the code stopped doing it** — the two dismissal paths `.transient` handled for free are now explicit: outside clicks via `outsideClickMonitor`, app deactivation via its own observer. Everything about the show/hide *animation* is still AppKit's; customising that is what made AppKit-initiated closes skip the animation.
- Button acts on **mouse-down**, which also wins the race against auto-dismissal when clicking the icon while open.
- `outsideClickMonitor` stays, and under `.applicationDefined` it is the only thing handling outside clicks. It also covers a case `.transient` never did: clicks on *other apps'* status items, since SystemUIServer-hosted extras don't trigger the activation-change signal. It skips clicks inside our own button's frame — global monitors do see those, despite the docs.
- `wantsHighlight` drives the status item's active background manually; `NSButtonCell` clears `isHighlighted` on mouse-up *after* our action, so it's reasserted at three points across the release. **Cosmetic only, never consulted for behaviour** — that's what makes it not a repeat of the tracked-state mistake.

## Focus rings — settled after six attempts

Two independent mechanisms were being confused for one:

1. **SwiftUI focus effects** — `.focusEffectDisabled()`, honoured only where SwiftUI draws (i.e. `.buttonStyle(.plain)`).
2. **AppKit focus rings** — `NSView.focusRingType`, unreachable from SwiftUI. `Picker`, `Toggle` and `Slider` are SwiftUI *API* backed by `NSPopUpButton`/`NSSwitch`/`NSSlider`, so they fall here.

`.focusEffectDisabled()` was a half-fix that made things worse — Tab moved through nine controls but only five stops were visible. **Removed.** The real bug was never the rings but **unrequested focus on open**: `NSPopover` assigns first responder when it shows. Cleared inline in `togglePopover` right after `show()` returns, plus a next-run-loop retry and `popoverDidShow` as a catch. Focus from Tab or "P" clears itself after 3s idle.

Goal is **"no rings until you ask"**, not "no rings ever" — a ring on Tab or "P" is correct feedback. **Do not add another ring-suppression attempt.**

## The popover's hosting controller MUST declare its size

`NSHostingController(rootView: PopoverView())` needs `sizingOptions = [.preferredContentSize]`. Without it AppKit places the popover for a size SwiftUI has not settled on yet, and the window then **grows up and to the left** as the real layout arrives.

Measured in a 20-line probe containing no larc code, on **both macOS 15.6 and 26.5**: every variant without a declared size came out 40pt left and 106–160pt high; every variant with one was exact. Both `contentSize` and `sizingOptions` fix it. Working backwards from two content heights, the size AppKit is handed first is about **186×346** regardless of the real content — the errors are exactly `finalHeight − 346` and `−(finalWidth − 186)/2`.

**It is not version-specific**, though it looks it. larc escaped it on 26 — presumably SwiftUI resolving the size before `show()` returns — and hit it on 15.6, where the popover sat 106pt too high with its top clipped off the screen. Nor is it screen-specific: a short screen (706pt usable) makes the clipping visible where a tall one (959pt) hides it, so changing resolution and hiding the Dock both appear to do nothing.

The signature is **a top that stays put while the bottom moves with content** — the window's origin was set once, for the wrong size.

- `.preferredContentSize` rather than a hardcoded `contentSize`: the popover's height legitimately varies, and a constant would need maintaining against every layout change.
- The debugging technique is worth copying. `CGWindowListCopyWindowInfo` reports window bounds with **no permissions at all**, so the status item and popover frames can be measured on a machine you cannot attach a debugger to — and a standalone probe that builds each configuration in turn and prints the offsets settles in one run what guessing could not in ten.

## Menu bar content is ALWAYS a fixed-size template image

Never `button.title`. Symptom was the popover jumping vertically; the decisive observation was that the shift tracks **image vs. number**, not volume level. The popover anchors to `button.bounds`, and an image-only button and a title-only button don't present the same anchor. `menuBarImage(drawing:)` renders both glyph and numeric flash into one 26×18 canvas, `isTemplate = true`, `title` permanently `""`. Symbols get an explicit `SymbolConfiguration(pointSize: 15)` so glyph differences can't reintroduce it. `statusItem(withLength: 30)` is necessary but was never sufficient alone.

## Now-playing section

- **Artwork** comes from `getMetaInfo`, fetched concurrently with `getPlayerStatus`. Its text fields win where present (plain UTF-8 vs hex). **Best-effort, never throws** — it's WiiM-specific and losing artwork must not cost transport state.
- **Placeholder metadata** is filtered by `cleaned()`. Devices send literal `"unknow"` (WiiM's own misspelling). Matched **exactly, never by prefix** — *Unknown Pleasures* is a real album. Artwork URLs additionally require a scheme, since `URL(string: "unknow")` succeeds as a relative URL. **XML entities are unescaped** — metadata arrives with `&amp;` and friends intact.
- **`sourceSubtitle`** is a last-resort second line — radio streams put the station name there while leaving artist and album as placeholders. Used only when both are unusable, dropped when identical to the title.
- **The tint is a sampled-colour gradient, NOT the artwork.** The image at low opacity was tried at 0.08/0.2/0.10 with 2pt and 6pt blur and disliked at every setting: a busy cover reads as noise, and its luminance is uncontrolled. See **Artwork colour** below for what replaced it.
- **Two translucent layers**, and *both* are now per-category (see below). The gradient carries colour, the watermark carries texture. Two weak passes, not one strong one. A **third** copy — a thumbnail in the status gap — was built and reverted; don't re-add it.
- **No cover falls back to the larc logo**, built as a real `Artwork` so it goes through the same palette, the same nine categories and the same two layers — nothing downstream knows it's a substitute. Identity is `larc-fallback:logo`, a scheme resolving to nothing, so it compares unequal to every real cover and the cross-fade works with no special case. Used for a missing URL *and* a failed download: an unreachable host and no host at all look the same. It measures luminance 0.978 / contrast 0.063 and yields **one** stop, so it lands in light + flat — the category to tune it in.
- **The logo dims while nothing is playing**; a cover never does. Gated on `showsAsPlaying`, not on whether artwork exists, because the two answer different questions: a cover with no music behind it doesn't happen, but the logo with no music behind it is the popover's most common state, and full strength there asserts "something is playing" when nothing is. Desaturated (0.2) as well as faded (`restingOpacity`), so it recedes rather than thinning. **Its fade needs its own animation key**: `Artwork` compares by URL alone, so "logo dimmed" and "logo bright" are the same value and the transition would snap.
- **`larc/Resources/` is copied into the bundle by `build.sh`** — the first thing it has ever carried besides the binary. The directory is allowed not to exist, and `Artwork.fallback` is nil when the resource is missing, so an older build simply has no fallback.
- **Watermark is full-bleed and SQUARE by derivation.** Art is 1:1 and `.aspectRatio(.fill)` covers, so any non-square frame crops it (at 226×198 it silently lost 14pt top and bottom). `watermarkWidth` is `popoverWidth` and the height is *defined as* the width, so a non-square frame is impossible. No corner rounding — at full bleed the popover clips its own corners and rounding cuts visible notches inside them. `watermarkFadeHeight` 28, absolute not fractional.
- **One download, two layers.** `Artwork.load(from:)` downloads, decodes and samples once. `Artwork`'s `==` compares only the URL, the right granularity for `.animation(value:)`.
- **Public `http` artwork URLs are upgraded to `https`.** ATS blocks plain-HTTP to public hosts *outright* — never attempted, so it is **not** a certificate problem and the trust delegate never runs. TuneIn returns both schemes on the same CDN host, which is why art appeared for some stations and not others.
- **Artwork accepts self-signed certs from private-IP hosts** (`PrivateNetworkTrustDelegate`). Plex returns `https://<lan-ip>:32400/…&X-Plex-Token=…` — a LAN IP with a self-signed cert that `URLSession.shared` rejects at the handshake.
  - **`NSAllowsLocalNetworking` does NOT cover this** — it exempts ATS *transport* rules; certificate trust is a separate gate.
  - **`LinkplayPlugin`'s `SelfSignedTrustDelegate` does NOT help either** — it matches the *device's* host, and artwork lives elsewhere. The scoping that makes it safe makes it useless here.
  - Scoped to **bare private/loopback/link-local IPv4 literals only**. Hostnames excluded even when they look local (`nas.local` resolves wherever DNS says). Verified against 16 cases including the `172.15`/`172.32` boundaries.
  - **Security trade, accepted by the maintainer:** an on-LAN attacker could capture a token in an artwork URL — but that token arrives *inside* the `getMetaInfo` response, itself fetched over self-signed HTTPS we accept unverified. Declining protects nothing and costs the artwork.
- **A side-by-side art tile was tried and reverted**: three 45pt transport buttons plus gaps is 159pt before any artwork, forcing the popover to 360pt. As a backdrop it costs no layout at all.
- **The popover's arrow cannot inherit the tint.** Drawn by AppKit's private `NSPopoverFrame`, so a `.background` on content stops at the content bounds. Routes are private-frame surgery (this popover has been blanked twice by AppKit surgery) or a custom panel (rejected). **Don't attempt it.**

## Artwork colour

The pipeline, in order: sample the cover → classify it → tone it → colour it → draw it. Every stage has a knob, and all of them live in one place.

- **16×16 sampling, not 4×4.** Each cell is an average, so the grid decides how much of the cover collapses into one number. At 4×4 a dark cover with a small bright accent averaged the accent into its background and the palette reported *grey* for a cover anyone would call green (deadmau5's SATRN). Sampling fixed *positions* instead was proposed and rejected — fixed points miss an accent that isn't where they look, which on that same cover is the middle.
- **Grey is discarded before ranking, not after.** A near-grey cell has an arbitrary hue, so hue-distinctness treats it as distinct from every real colour and it takes a stop. `saturationFloor` 0.12 — low, because the job is only "has a hue" vs "doesn't".
- **`contrast` is p90 − p10 of cell brightness, on 0…1.** Not max − min: one white logo cell would report a flat cover as maximally busy. Percentiles ask how much of the picture differs, not whether any of it does. `luminance` is the mean over **every** cell, including the ones the saturation floor rejected — the question is "how dark is this picture", and a dark cover's near-black background is most of the answer.
- **Nine categories, looked up — never interpolated.** Three luminance bands × three contrast bands. Bilinear interpolation across corners was tried and is what made the values unjudgeable: every slider nudged every cover a little and none of them moved one cover cleanly. The cost is a step at each threshold; the thresholds are themselves adjustable. Three bands rather than two because with one split most real covers sat near it, where a small change in the artwork flipped the whole treatment.
- **Exposure and contrast are defined once and applied twice** — as `.brightness`/`.contrast` on the watermark, and as the same arithmetic on the samples the tint is built from. Sampling the raw image left the gradient the colour of a picture nobody was looking at. Contrast is applied first so it pivots on the image's own mid-grey; the other order would let exposure move the point contrast pivots about, flattening the silhouette exposure is meant to reveal.
- **Saturation is capped per stop, by that stop's own brightness.** A bright saturated stop turns the whole popover pink; an equally saturated *dark* stop is just a deep colour. So the ceiling interpolates between `atDark` and `atBright` rather than being one number.
- **Vibrance is `s + k(1 − s)`, and it runs before the ceiling.** Saturation cannot exceed 1 — it's `(max − min) / max` of the channels, so at 1 the darkest channel is already 0. What can change is the *shape*: headroom-proportional moves a muted stop a long way and a vivid one barely at all, where a flat multiply clips the vivid ones first. The ceiling keeps the last word deliberately; a boost that could overrule it would reintroduce the pink popover.
- **Exposure and contrast can eat the whole range.** At contrast 2.5 and exposure +0.8, toned brightness is `clamp(2.5b + 0.05)` — anything above 0.38 pins to 1.0, where saturation is held at the ceiling and vibrance cannot move it. `resolvedStops(for:)` returns HSB rather than `Color` precisely so this is visible: a stop sitting exactly on the ceiling at brightness 1.00 is the signature. **If vibrance "does nothing", check the stops before changing vibrance.**

### Where the values live

- **`ArtworkDefaults.swift` is generated and is the only source of truth for the numbers.** `ArtworkTuning` declares each knob and documents why it exists; it holds no values of its own. That split is what makes the generator safe — it emits the whole file rather than patching a region, and nothing worth keeping is in the file being overwritten.
- **`TuningWindow` is `LARC_DEV` only** (`./build.sh --dev`). It shipped in release while the layers were being worked on; it writes to the source tree and `#filePath` bakes the compiling machine's absolute path into the binary, so it must never reach a user. `ArtworkTuning` keeps the values in release and loses persistence, the Current/Latest comparison and the writer.
- **Stored edits record the baseline they were made against.** Without that, editing `ArtworkDefaults.swift` and rebuilding did nothing on a machine that had ever opened the window — the UserDefaults blob silently reinstated the old numbers. When the baseline no longer matches, the source wins.
- `check.sh` type-checks **both** configurations, because this file is mostly `#if` in release.

## Transport controls

- `TrianglePairIcon` builds prev/next from two mirrored `play.fill` glyphs so the triangles animate independently. **One continuously-animated Double per triangle (`slots`), with position/scale/opacity as pure functions of it.**
  - **Don't reintroduce phase-scheduled sub-animations**, and **don't reintroduce any scheduled reset or wrap of the slot values.** This exact class of bug has been hit twice from two different timing-based approaches: first triangles stuck at an intermediate scale under rapid presses, then all three permanently vanished as cancelled wraps let values drift outside the visible range. The fix wasn't better scheduling, it was not needing any: every property normalises the raw slot via `.truncatingRemainder(dividingBy: 3)`, so rendering is correct for any value at any click speed.
  - `spacing` 14.4 (< `triangleSize` 17.6, so the resting pair touches), `duration` 0.55s. A static container offset of `±spacing/2` centres the pair in its 45×45 hitbox — at rest the triangles sit at 0 and ±spacing, so the centroid was ~7pt off.
  - **Under `.buttonStyle(.plain)`, hit testing follows the drawn content, not the frame.** A 45×45 `.frame` applied *outside* the Button's label left clicks on the inner triangle missing entirely. The frame has to be on the label.
- **Play/pause flicker on track change** needed three fixes together: `.loading` counts as playing (Linkplay reports `"load"` while buffering); `next/previousTrack` only records a timestamp rather than asserting `.playing` (which lied when the user had paused); and `apply(_:)` guards `status.state` for 3s after a local transport command — **filtered, not blanket**, suppressing only reports failing `isSettled` (`.stopped`/`.loading`/`.unknown`). Blanket suppression made the play glyph lag the audio by up to 3s.
  - Deliberate consequence the maintainer prefers: pressing play with **nothing queued** still reverts to the play glyph, after the guard window. That revert is the device honestly reporting it can't play.
- **Volume and play/pause jumping on device switch**: `rebuildPlugin()` used to `status = nil`, so the slider slammed to zero for one round trip. Fix: **keep the outgoing device's status as a placeholder**, clearing only when there's no device. Both guards plus `pendingVolume`/`draggingVolume` are reset on switch, or they'd hold the outgoing device's values over the incoming device's first poll.
- **A stale cache doesn't just display wrong, it writes wrong.** Linkplay has no relative volume command, so `stepVolume` sends `vol:(cached + step)` as an absolute. The poll timer doesn't run while the Mac sleeps, so on wake the cache could be hours old and the first press *overwrote* the device with it — cache 20 against a device at 45 sets 21, and it jumps upward just as readily. `DeviceController` observes `NSWorkspace.didWakeNotification` and polls once on wake; the fingerprint is rechecked at the same time, since the network may have changed while asleep. One request per wake, not a new interval.
- **Menu bar icon lag** was a `@Published` timing quirk, not network latency: the publisher fires on `willSet`, so sinks reading the property fresh saw the *old* value and looked permanently one change behind. Fixed by deferring each sink's read one run loop tick.
- **Volume slider is a plain `Slider`, always visible, no hover behaviour.** Hiding it hid the *track* too, leaving no way to read the level. SwiftUI can't hide a `Slider`'s knob alone; that needs ~80 lines of hand-built slider or an `NSSlider` representable. **Don't rebuild this** — if it comes up, say what it costs first.
- **Track controls are hidden on passthrough inputs** — line-in, optical, phono — where there is no stream for play/pause to act on. Hidden rather than removed, so the popover's height can't depend on which input is selected. `PlayerStatus.supportsTransport`, and **not `isExternalSource`**, which groups Bluetooth and HDMI with optical: right for metadata and seeking, wrong for transport. Bluetooth relays over AVRCP and HDMI reaches the TV over CEC, both tested working. An unrecognised mode returns *true* — AirPlay and Spotify Connect arrive as their own numbers, and a useless button on an unknown source is cheaper than a missing one on a working source. (Coax isn't an input on this hardware; it's an output.)
- Mute button needs an explicit **height and font size**, not just width — SF Symbols don't share vertical metrics even at nominally the same size, and without both the popover's height shifted every time mute toggled.

## `MarqueeText`

Two copies separated by `gap` (28) scroll exactly one lap, so resetting is invisible.

- Width measured with **`NSAttributedString`, synchronously** — the `GeometryReader`+preference version had no way to prove the measurement arrived, and a zero width silently disables scrolling instead of failing visibly. Cost two debugging rounds.
- **The offset is a pure function of elapsed time, not an animation.** A `TimelineView(.animation(paused:))` samples one clock shared by both lines. The previous per-line `withAnimation(.linear)` caused three bugs that all dissolve here: lines drifted against each other (two timelines aren't frame-locked), pausing playback couldn't pause the scroll (a running animation can't be frozen), and a track change let SwiftUI *retarget* the in-flight animation so incoming text raced into place.
- `anchor` is shared and `frozenAt` freezes: on resume `anchor` shifts forward by the stopped interval, so travel **continues** rather than restarting.
- `fade` (8) is both the edge gradient and the text's leading inset, and **must equal the caller's horizontal bleed** — it references `Metrics.backgroundPadding` rather than repeating it.

## Hotkeys

`PopoverHotkeys`, all keyCode-based so Shift doesn't matter:

| Key | Action |
|---|---|
| ↑ ↓ or − = | Volume ±1 step |
| ⌘/⌃ + 1…0 − = | Volume preset: N×3 up to N×14 (N = Volume Step), clamped to 100 |
| M | Toggle mute |
| P then Space | Focus the device picker, then open it. Badge reads `P ␣` as one box — sequential steps, not alternatives. |
| J / K / L | Previous / Play-Pause / Next |
| ⌥← ⌘← / ⌥→ ⌘→ | Previous / Next |
| ? | Show hint badges, auto-hide after 3s |
| ← → and Tab | **Not** hotkeys — native behaviour preserved. Tab still restarts the focus-idle timer and shows badges. |

- ↑/↓ while the picker has focus is still volume, **not** device selection. Intentional.

**Media keys are gated per key, not all-or-nothing** (`MediaKeyMapping.action(for:)`). Returning nil passes the event to the Mac untouched.

| | passthrough input | unreachable / no device |
|---|---|---|
| volume, mute | Larc | Mac |
| play, next, prev | Mac | Mac |

Volume and transport are separate questions: on optical the WiiM is still the amplifier, so its volume is exactly what the keys should move, while transport there only gates its output and leaves the source playing. Unreachable passes *everything* through — the key used to be consumed and then silently do nothing, so a sleeping WiiM made the Mac's own volume keys look broken. The gate reads `DeviceController.currentInput`, which is held across idle; `status?.input` blinks to nil every time playback stops.

**Not detectable: whether the Mac itself is playing.** The case that would justify handing everything back — Spotify on the Mac, WiiM idle — needs the private MediaRemote framework. `MPNowPlayingInfoCenter` only reports your own app. Don't re-derive this.
- Badges are overlays drawn as part of their row, so a later `Divider()` sibling painted over them — fixed with `.zIndex(1)` on each badge-carrying row **in the body VStack**. A `.zIndex` inside `hotkeyHint` cannot fix this; zIndex only orders against siblings in the same container.
- Each badge needs `.fixedSize()` or a 2-glyph badge like "⌘←" wraps onto two lines (symbols have no word boundary).
- The device picker's badge uses `distance: 22` and requires the matching `topGutter` 26 — badges draw outside their control's bounds and would otherwise land on the popover's chrome.

## Liquid Glass (macOS 26)

**Deployment target stays 14.0.** Standard controls adapt for free: `build.sh` links the 26.5 SDK and `Info.plist` has no opt-out key, so system-drawn controls pick their look at runtime. Hand-styled surfaces need a **runtime** branch (`if #available(macOS 26.0, *)`, never `#if`). `glassEffect` lives in **SwiftUICore**, not SwiftUI.

- **`Glass.tint(_:)` is not a low-opacity wash.** `.glassEffect(.regular.tint(.orange))` renders a near-solid saturated block that crushed body text unreadable. Don't reach for it expecting one.
- **Deliberately not converted:** `ActionRow`'s hover (a tint, not a floating material — glass-on-glass), and glass bubbles behind the transport buttons (tried, reverted on sight, same objection).
- **Skipped:** `.buttonStyle(.glass)` — it would restyle transport buttons from SwiftUI-drawn to system-drawn, reopening the focus-ring question.
- **Untried:** `GlassEffectContainer`, which would blend adjacent badges rather than showing separate chips.

---

# Device settings and presets

`DeviceSettingsModel` holds input/output/channel/room-correction. Output, channel and RC are **deliberately not on `DeviceController`'s 2s poll** — nothing but a person changes them, so they're read when a screen opens.

- **Input is the exception, and is live.** The *device* changes it with nobody at the Mac: an alarm or auto-sense switches to Wi-Fi, and a value read once when the screen opened kept claiming Optical for hours. **Verified against a real overnight alarm on 2026-08-08** — the popover read Wi-Fi unprompted the next morning. It costs no extra request — `currentInput()` reads `getPlayerStatus`, which the transport poll already fetches, so `DeviceSettingsModel` tracks `DeviceController.$status` and `plugin.currentInput()` is now used only by `applyPreset`. A local change owns the value while `pending == .input`; after that the device's report wins, which is also how a *refused* switch corrects itself.

- **Woken in `LarcApp.init`, not lazily.** It's a lazy static, and nothing on the main screen touches it, so its `$selectedID` subscription — whose whole job is to start loading the moment a device is chosen — didn't exist until the Controls screen was first built. The screen it was meant to have filled.
- The `$selectedID` sink dispatches to the next run loop: `@Published` fires on `willSet`, so the controller hasn't rebuilt its plugin yet.
- **`identify()` returns `DeviceIdentity?`.** It used to return an identity with every field nil on failure — indistinguishable from a device that answered without naming itself, so `isIdentified` read true and `AudioOutput.known(nil)` returned six unlabelled numbers. A failed load also clears `loadedForDeviceID` so it retries; previously the only way back was to select another device and return.
- **Pressing Controls before its settings arrive doesn't navigate.** The pill holds the press — label fades, glyph breathes — and pushes when the model reports ready, or after `controlsWaitTimeout` (6s) regardless.
- Every setter is **optimistic then verified**. On failure it reverts *and re-reads the device*: `revert()` restores what we had before the attempt, which is only right if the write did nothing.
- **A failed read and an empty answer are different, and `try?` collapsed them.** `loadIfNeeded` fires four concurrent reads; one dropped request drew a blank control, and because only a nil `identity` cleared `loadedForDeviceID`, nothing ever asked again — the only way back was to switch devices and return. Reads now go through `attempt`, which keeps `(value, didFail)`. A *failure* clears the guard and triggers one retry after 1.5s; an *empty answer* does not, since that is settled and retrying it would poll forever. `retrying` bounds it to a single attempt so a consistently failing device can't drive a loop.
- **Fault injection is how this is tested** (`larc/FaultInjection.swift`, `LARC_DEV` only): `open build/Larc.app --args --fail-reads 0.5` throws that fraction of *every* device request inside `LinkplayPlugin.send`. Fractional on purpose — the interesting case is losing one read of four, which powering the device off cannot produce.
- **Tiles breathe while a change is confirming, starting after 1.5s.** Almost every change lands on the first read, so showing it immediately would flash a breath on every press and the motion would stop meaning anything.

## `OK` means nothing — and neither does one readback

Every setter verifies by reading back, because this hardware answers `OK` to values it silently ignores.

**But an immediate readback races the device.** Picking Line Out on an Ultra switched the device, then reported "refused", reverted the UI, and wrote value 2 to the refused list so the tile disappeared. `confirm()` retries — first attempt immediate, then up to 24 more at 250ms (6s). The outcomes aren't symmetric: waiting too long costs a moment on a change that already happened; giving up early costs a **persisted** refusal.

**A refused output is flagged, not deleted.** `known(for:)` unions refusals in; the tile carries a caution dot and stays selectable. A refusal can be wrong, and a correct one goes stale (firmware adds an output, a Bluetooth speaker gets paired) — a value nobody can select can never prove itself right again. Deliberately a caution rather than `disabled`, which would claim "not for you" on one unconfirmed readback.

`setChannelMode` verifies too, since it sent and returned and a refused mode failed silently — the opposite of the output bug and worse, because nothing on screen ever said the change hadn't happened.

## Presets

- **Names must be unique.** `add()` takes the lowest unused number — `presets.count + 1` repeats as soon as anything is deleted. A duplicate typed deliberately is **refused, not corrected**: the editor shows "A preset with this name already exists" in red and disables back. Auto-suffixing was tried and produced "Preset 2 2" — a name nobody typed. Comparison ignores case and surrounding whitespace.
- Closing the popover abandons an invalid name: the field writes straight through to the store, so the editor remembers the name it opened with and restores it.
- **Presets are global, and output is stored by NAME.** Storing the number was a silent bug: 2 is Line Out on an Ultra and the speaker terminals on an Amp, so a preset built on one and applied to the other set output 2, the readback confirmed 2, and the audio went to the wrong jack. It succeeded at the wrong thing. A name either resolves on this model or it doesn't, and a preset naming a jack this device lacks **skips** output. `outputValue` survives only for presets saved before this and for unmapped hardware.
  - Everything else already degraded safely: input is name-matched and verified, channel mode is model-independent, RC is matched against the device's own profile names, volume is universal.
  - A preset whose output isn't available here reads **"Line Out (not here)"** in the list, so it declares what it will skip before you press it.
- Every field is optional and nil means "leave it alone" — that's the difference between a preset and a snapshot.
- The icon picker rebuilds Apple's Focus/Messages layout (preview, name, colour grid, symbol grid). Apple's own is private API; this is a lookalike.

---

# Linkplay HTTP API

`http(s)://<ip>/httpapi.asp?command=…`. HTTPS first with a trust delegate scoped to that host, HTTP :80 fallback. Discovery is mDNS `_linkplay._tcp` (port 59152; TXT carries `uuid`, `MAC`, `security: "https 3.0"`).

Test with `curl -k "https://<device-ip>/httpapi.asp?command=<cmd>"` — Claude's sandbox can't reach the LAN, so the maintainer runs these. Device addresses live in `PRIVATE.md`, which is gitignored; read it when you need one. **Confirm which model an address is before doubting a setter** (`getStatusEx.project`) — a whole "channel mode is broken" thread came from testing one device while changing the other.

## Methodology

- **The device is its own oracle**: an unrecognised command replies literally `unknown command`. `tools/enumerate-commands.py` exploits this. But:
- **Commands are matched by fixed-length prefix**, so *identical responses across many spellings are one command, not many*. Always include nonsense controls and binary-search the prefix boundary. Without controls, one session "found" 18 commands that didn't exist.
- **`{"status":"Failed"}` ≠ `unknown command`.** Failed means it exists and wants a different call.
- **Probe setters safely** by passing back the value the getter already returned — a no-op if real. But the sentinel trick is only safe against commands that *validate*: `setRoomCorrection:larcProbe0` returned `OK` and overwrote a real stored value.
- **Break the app's connection and read its telemetry.** With mitmproxy `--mode local:MuzoHome`, the WiiM app reports failures to Firebase **in plaintext**, carrying `commandName` and `errorDescription`. That's where `EQGetLV2SourceBandEx` and `EQSourceOff` came from, after 380 name guesses failed. Extract with `mitmdump -nr FILE --flow-detail 3` and grep for `commandName`.
- **The two capture modes answer different questions.** System proxy decrypts `httpapi.asp` but the app makes **no settings calls under it** (120 requests, all polling). Local mode times out the device's TLS so the app fails — and its failure names the API. **Local mode for a command's NAME, system proxy for its PAYLOAD.** `tools/capture.sh` runs the proxy version and restores the network on exit.
- **A telemetry command name is not proof of an HTTP command.** `setSoundCardOutputMode` appears in the app's own code and is *not* an HTTP command; the app translates it to `setAudioOutputHardwareMode` before sending.
- **Never write a probe that can reach full volume.** An early sweep hit 100 on the maintainer's speakers. `tools/probe-volume.py` enforces a ceiling inside the single function that sends a volume, validates the whole sequence before sending anything, and requires `--test-limits` plus an explicit `--max`.

## Verified commands

**Transport / status.** `getPlayerStatus` (volume, mute, `status`, `mode`, `curpos`/`totlen`, `loop`, `plicount`), `setPlayerCmd:vol:N|mute:0|1|onepause|next|prev`, `getMetaInfo` (artwork + clean text), `getStatusEx` (`project` = model, `firmware`, `max_volume`, `plm_support`). `getPlayerStatusEx` returns an **identical** field set — no reason to use it.

**Volume is whole numbers only.** `setPlayerCmd:vol:` accepts a decimal and answers `OK`, but the device quantises. Volume Step options stay integers.

**Inputs — `setPlayerCmd:switchmode:<name>`, and `OK` means nothing.** Verify by reading `getPlayerStatus.mode`.

| switchmode | mode | note |
|---|---|---|
| `wifi` | 10 | network streaming |
| `line-in` | 40 | |
| `bluetooth` | 41 | |
| `optical` | 43 | |
| `HDMI` | 49 | **uppercase, and only uppercase** — 16 lowercase spellings all answered `OK` and stayed on Wi-Fi |
| `phono` | 54 | Ultra only |

**`mode` is the only input field, and it is fast and stable** — sampled every second for ten seconds after a switch it read 43 (optical) and 10 (wifi) from the first second, with no settling period. Two things that look like alternatives are not: `getNewAudioOutputHardwareMode.source` held 0 across both inputs, playing and stopped, for every sample — so it is **not** the selected input and **not** signal presence either. The single `3` seen once is unexplained and was never reproduced; treat the field as not understood and don't build on it. `MCUKeyShortClick:1` answers `OK` while changing nothing, so it is not a wake command.

**On a passthrough input, `status` is the device's own output gate.** On optical, `setPlayerCmd:onepause` toggles `status` between `play` and `stop` and mutes or unmutes the speakers — the source keeps running throughout, so nothing was paused, only silenced. `mode` stays 43 the whole time. This is why transport is hidden on passthrough inputs and why media keys should reach the Mac there: when the Mac is what's feeding the optical cable, pausing the Mac is the thing the user meant, and gating the WiiM's output just makes audio disappear while the Mac plays on.

**`mode` conflates the selected input with what is playing through it, and idle is `-1`.** A WiiM with nothing playing reports `mode: -1, status: none` *whatever* input is selected — so `-1` is not an input and must not clear one, or stopping playback appears to unplug the cable. Everything non-negative that isn't in the table above is network playback under its own number (AirPlay, Spotify Connect, DLNA, the device's own queue), so `AudioInput.init(mode:)` resolves those to `.network` rather than nil. Returning nil there is what left Controls with no input tile lit on a working device.

`co-axial` is **not an input** — it's an *output* on the Ultra, and the device quietly gave optical instead. **USB is not an input mode** — all 16 spellings failed; the Ultra's USB port is browsable storage reached through the play queue.

**Outputs — `setAudioOutputHardwareMode:<n>`, getter is `getNewAudioOutputHardwareMode`.** Note the asymmetry: the getter carries `New` and the setter doesn't; guessing otherwise returns `unknown command`.

**The mapping is PER MODEL — the same number is a different jack.**

| value | WiiM_Ultra | WiiM_AMP |
|---|---|---|
| 1 | Optical | rejected |
| 2 | **Line Out** | **Speakers** |
| 3 | Coax | rejected |
| 4 | Headphones | rejected |

`AudioOutput.known(for:)` returns **empty** for unrecognised hardware — offering nothing beats offering jacks that don't exist. The app's own display order is not the numeric order.

**Channel mode — `getChannelMode` / `setChannelMode`.** 0 Stereo, 1 Left, 2 Right, 3 Mono, mapped by ear on the Ultra and **re-confirmed audible on 2026-07-30**; model-independent as far as tested. A round of "the channels do nothing" turned out to be a test run against the Amp's IP while the Ultra was the device being changed — the readback was honest throughout. Check which device an IP is before doubting a setter: `getStatusEx.project`. **Treat as an observation, not a contract** — nothing enumerates the valid set, so `ChannelMode` wraps a raw Int and renders an unknown value as "Mode 5" rather than dropping it. Amp mapping unverified by ear.

**Unpublished setters that work:** `setMaxVolume:<n>` (a genuine feature candidate). `setVolumeControl:<n>` exists but its **semantics are unverified and potentially dangerous** — on Linkplay hardware this name most likely selects fixed vs variable line-out level, so a wrong value could send full-scale signal into an amp. Don't experiment casually.

**Confirmed absent** (don't re-probe these spellings): `setPromptStatus`, `setPrivacyMode`, `setAutoSense`, `setPassthrough`, `setPlayMode`, `setAudioChannelConfig`, `getChannelAudioOutputHardwareMode`, `getEqualizer`, `GetMetaInfo` (capital G).

## RoomFit / room correction — solved, read and write

`tools/roomfit.py` implements it. Four facts no amount of guessing would have produced:

```
list      EQv2GetNewList        {pluginURI, EQLevel}
read      EQGetLV2SourceBandEx  {pluginURI, EQLevel, source_name}
select    EQSetLV2SourceBand    {pluginURI, EQLevel, source_name, EQStat,
                                 Name, channelMode}      <- NO bands, NO Ex
disable   EQSourceOff           {pluginURI, EQLevel, source_name}
```

`pluginURI` is `http://moddevices.com/plugins/caps/EqNp`, `EQLevel` 2.

1. **`source_name` is mandatory and state is per input source.** Eight slots (`wifi`, `default`, `line-in`, `optical`, `bluetooth`, `co-axial`, `hdmi`, `phono`). Omitting it writes to `default`.
2. **Selecting a profile costs ONE call, on the `default` slot only.** Writing `default` propagates to the rest. `EQv2Load` is **unnecessary** — the device already stores each profile's coefficients. The `wifi` slot is **inert**: writing it alone changed neither audio nor app *with music playing over the network*. Don't "optimise" by writing it. (The earlier belief that all eight slots were needed came from a test that changed eight things at once.)
3. **The reader has `Ex`, the setter doesn't.** Asymmetric and undiscoverable; the `Ex` spelling was tried first and rejected.
4. **The naming call must NOT carry band data** — with bands the request line hits **HTTP 431**; at 148 bytes it succeeds.

**Enabling is implicit:** any `EQSetLV2SourceBand` write turns correction on whatever `EQStat` says (`"Off"`/`"0"`/`"false"` were all tried, all switched it on). `EQSourceOff` disables while preserving the selected name, so re-enabling needs nothing cached. `EQOn`/`EQOff` return `OK` but are level-1 only and never reach this stage.

Devices report `source_name` in **mixed case** (`"HDMI"` on the Amp, `"wifi"` on the Ultra) while arguments are lowercase — match case-insensitively. Confirmed on both models, so the API is general.

**Creating profiles needs the phone's microphone and is out of scope.**

Superseded, don't re-derive: `getRoomCorrection` is a **vestigial opaque string slot** (`setRoomCorrection:<anything>` returns `OK` without validating and echoes it back; the `{"RC_Version":""}` everyone read as a response is the stored *value*). `RoomCorr` is a distinct handler that rejects every argument tried. Neither is where RoomFit lives.

## Per-band EQ

`EQGetBand`/`EQGetBands` return all ten bands with values, plus `pluginURI` showing the firmware runs the MOD Devices CAPS `Eq10HP` plugin — so there is a real parametric engine underneath, not only the 24 stock presets. **This overturns the long-standing claim that per-band gain is unsupported over HTTP.** `EQGetList` returns 24 stock presets, identical on both devices. `EQOn`/`EQOff` work. `EQGetStat` is recognised but returns `Failed`.

Unexplored, named only in telemetry: **`EQv2SourceLoad`**, **`EQChangeSourceFX`**, `setSpdifAutoSenseEnable`.

## What the app talks to, and what it doesn't

Eight captures: **most of what the WiiM app does never touches the device.** Content browsing is direct, service by service — Plex, vTuner, SoundCloud, YouTube. **There is no WiiM browse API to reverse-engineer**; if larc ever browses Plex it talks to Plex and plays via `setPlayerCmd:play:<url>`. Updates and account are cloud too.

Device control is two surfaces only: `GET /httpapi.asp` and UPnP on :59152 (`rendertransport1`, `rendercontrol1`, **`PlayQueue1`** — the queue API, and UPnP is self-describing, so `tools/enumerate-upnp.py` can read it without any capture).

`_sc` in telemetry names the view controller, which says which screen a call came from. **LPRC = LinkPlay Room Correction.** Unexplored cloud endpoint: **`POST /autoEQ/getConfig`**.

## Still unmapped

`plm_support` is the input-capability bitmask (Ultra `0x2b10416` vs Amp `0x2b00416` differ in **bit 16**, almost certainly phono). **One bit identified; don't guess the rest** — a wrong map offers inputs the device lacks. No command enumerates inputs; all ten `get*List` guesses were `unknown command`. `source` and `audiocast` from the output getter are not understood.

---

# Status and open work

**Built and working:** discovery, transport, volume, media keys, hotkeys, artwork, onboarding, the navigation stack, Controls (input/output/channel/RC), Presets with editor and icon picker, the Dev gallery.

**Open, in rough priority order:**

**Open work lives in `ROADMAP.md`, not here** — it was drifting out of step in two places at once. This file records what was decided and why; that one records what hasn't been done yet.

## Larc Keys plan (App Store split)

Two free targets sharing one codebase, split only where App Sandbox actually blocks something.

- **Larc** (App Store): sandboxed, network-client + `NSBonjourServices`. Excludes `MediaKeyTap.swift` entirely.
- **Larc Keys** (direct download): current unsandboxed build, Developer ID signed and notarized. Own bundle ID and display name. The name flags the actual differentiator rather than implying a paywall — needs one explicit "still free" line wherever mentioned.

**Keys-exclusive is exactly:** anything needing a *consuming* CGEventTap plus Accessibility. No entitlement fixes this.

**Not Keys-exclusive:** the Carbon global hotkey (sandbox-safe, no TCC prompt), and everything else — EQ, output routing, artwork, Launch at Login. **Media keys while the popover is open was tried and abandoned** (`PopoverMediaKeyMonitor`, deleted): physical volume keys are handled at the CoreAudio/HID layer, below where a local monitor can observe or suppress them. For volume there is likely **no App-Store-safe way** to take the keys from the Mac. `PopoverHotkeys` solves the in-popover case with letters instead.

Practical cost: code and testing are nearly free (media keys already sit behind a toggle + permission state). The real recurring cost is a second App Store Connect listing and a 1–3 day review per release.

**Watch/iPhone companion** (separate future project): a Watch can't pair to a Mac, so it means an iPhone app first — which could hit `httpapi.asp` directly over LAN, bypassing the Mac. `DevicePlugin`/`LinkplayPlugin`/`PlayerStatus` are UI-independent enough to move into a shared Swift Package. Not scheduled; noted so the idea isn't lost.
