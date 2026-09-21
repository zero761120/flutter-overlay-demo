# flutter-overlay-demo

[繁體中文](README.md) · **English**

A Flutter spike for an Android floating ball (AssistiveTouch-like). Personal use, not a product.

The ball is draggable and snaps to the nearest edge (toggleable); tapping it opens a menu with:
set tap target, start/stop auto tap (300ms interval), screenshot, **record a flow**, clear
recordings, back to app. Whatever the overlay does is reported back to the host app and listed
there. Theme and locale follow the system (light/dark, Chinese/English); colors follow a blue
theme reused from another project.

**Android only** — iOS has no public API for drawing on top of other apps.

## Two independent permissions

| Permission | Used for | How it is granted |
|---|---|---|
| `SYSTEM_ALERT_WINDOW` | the overlay window itself | system settings page, **no runtime dialog** |
| Accessibility service | taps / screenshots / recording | Settings → Accessibility, manually |

## Build

```bash
fvm flutter pub get
fvm flutter build apk --debug
```

## Recording a flow

Subscribes to accessibility events, records what the user does in other apps, and writes it to
JSON. The point is to turn "what can actually be scraped" from guesswork into something you can
look at — how much an app exposes **depends entirely on how that app was written** (whether it
sets ids or `contentDescription`, standard widgets vs. custom drawing; a Flutter app exposes only
its Semantics tree, WebView content only if enabled). There is no spec to consult, so one
recording beats ten articles.

Use it: panel → "Record a flow" (the panel collapses) → operate the target app → come back and
stop, or just close the overlay from the host app (recording stops and saves itself). The host
app's "Recordings" screen shows the list → the steps (taps only by default) → the raw JSON
(collapsed, truncated).

Step labels prefer `contentDescription` over `text`: measured on the calculator, every button's
`text` is null and only `contentDescription` carries anything — without that field the whole
recording would be a column of blanks.

Files live in app-private internal storage, newest five kept. On a debug build:

```bash
adb exec-out run-as com.louis.overlay_demo ls app_flutter/
adb exec-out run-as com.louis.overlay_demo cat app_flutter/flow-<timestamp>.json > flow.json
```

## Before you use it

This tool requests two high-privilege permissions (overlay window, accessibility service), can
simulate touches, capture the screen, **and record other apps' on-screen text**. Those
capabilities are official Android APIs and neutral in themselves, but **how they are used is the
user's responsibility**: on your own device and your own accounts there is no issue; using them
to interfere with someone else's system, to bypass protection measures, or in breach of a
service's terms of use is on you.

A few things are done on the privacy side: every capture path skips nodes where `isPassword()`
is true; recordings go to app-private internal storage rather than external; `allowBackup` is
off — Auto Backup's default scope **is** internal storage, so leaving it on would close the front
door and leave the back one open; and event payloads travel through an in-process queue rather
than a system broadcast, so no other app can passively receive them.

The author accepts no liability for how it is used (see `LICENSE`).

## License

This project is MIT (see `LICENSE`).

The two packages under `packages/` are **modified copies** of third-party code, originally by
Iheb Briki under the MIT license; each keeps its own `LICENSE` file intact. Every change is
marked with a `LOCAL PATCH` comment in the source; the what and why are in the next section.
These fixes address genuine upstream defects that have not yet been reported upstream.

## Locally patched third-party packages

Two packages are vendored with fixes (`packages/`, wired through `dependency_overrides`). Most of
the defects share a cause: **upstream assumes it is only ever registered against one engine**,
while this app has two (the host app and the overlay).

### `flutter_overlay_window` (copy of 0.5.0)

**Message routing** — `WindowSetup.messenger` is a static field, yet it is assigned in
`onAttachedToEngine`. The plugin registers against both engines and the later one (the overlay)
wins, so `OverlayService` forwarded the overlay's `shareData()` **straight back to the overlay**
and the host app never received anything. The assignment moved to `onAttachedToActivity` — only
the host engine ever gets an Activity, which is the one place the two can be told apart.

**Rotation** — the overlay window is not an Activity, so it stays where it was when the display
rotates. Measured: dragged to `y=2084` in portrait, then rotated to landscape where the viewport
is only 1033 tall — the ball ends up entirely off-screen and unreachable. Added
`onConfigurationChanged` to clamp it back. Dart's `didChangeMetrics` **is not a usable hook**:
the ball's own window is a fixed 48dp and its viewport metrics do not change on rotation, so the
callback never fires.

### `flutter_accessibility_service` (copy of 1.2.0)

Nine defects, all found by measuring on a real device:

| Defect | Consequence |
|---|---|
| `nextTexts` declared and shipped, **never populated** | `nodesText` is a dead field, always empty |
| Sub-node `capturedText` put a raw CharSequence | null stringified to the literal `"null"` |
| Dart called `map['capturedText'].toString()` unconditionally | same |
| `contentDescription` never sent at all | icon-only buttons have no text, so a whole class of widgets is invisible |
| Tree depth hard-capped at 15, not settable from Dart | measured truncation; the leaves that carry the text get dropped |
| Events with a null `getSource()` dropped entirely | **clicks almost always arrive with `source=null`**, so that whole class vanished silently |
| Broadcast was a bare signal with the payload in one shared-prefs slot | back-to-back events overwrote each other |
| `performGlobalAction` checked only the settings flag and returned `true` unconditionally | a failed action looked like a successful one |
| `onServiceConnected` called `requireNonNull` on an uncached engine | guaranteed NPE when the process is started by the service → crash loop → the service never connects |

The last one was the hardest to find: the system settings screen still lists the service as
enabled, but it never actually connected, and `dispatchGesture` handles that by **silently
returning false with no log at all**. It took a log line added in the native code to see both the
`source=null` behaviour and the crash loop.

## Known issues

**When the window changes size or position, the picture lags the parameters by ~280ms.**
Measured: the LayoutParams reported by `getOverlayPosition()` are final within 1ms, but the
window on screen takes ~283ms to catch up — the move happens at the surface/compositor layer,
out of Dart's reach.

Three mitigations are in place. **All of them mask the symptom; none fixes the cause**:

1. Draw nothing during the transition (`_BallMode.switching`)
2. `await endOfFrame` before touching the window, so what the system stretches is a blank frame
   rather than the ball
3. Reveal only after the geometry has landed (`kCollapseRevealDelay` 300ms /
   `kExpandRevealDelay` 200ms); both values were measured frame by frame

The two edges used to feel different for the same reason: expanding always anchors the window at
(0,0), so a ball on the left needs no horizontal move while one on the right travels almost a
full screen width. Item 3 evens them out.

**The recorder's tree dedup can skip a screen**: the fingerprint is only
`packageName + child count + first 8 text fragments`, so two visually different screens that
happen to match on those are treated as "unchanged" and the tree is skipped, leaving only the
event itself.

## Traps hit along the way (all documented in `lib/main.dart` comments)

- `showOverlay` takes width/height in px, while `resizeOverlay` and `startPosition` take dp
- `resizeOverlay` has no MATCH_PARENT sentinel for height (upstream's condition is always true),
  so it only accepts a real dp value
- Align the window with `topLeft`; centered gravity measures against the parent frame with the
  system bars removed, which differs from `display.size` by one inset
- `closeOverlay` does not rebuild the isolate (the engine is cached), so `initState` never re-runs
- `closeOverlay` also gives the overlay's Dart side **no signal at all** — it only tears down the
  native view. Timers and subscriptions there must check `isActive()` themselves, or they keep
  running after the window is gone, with the stop button no longer reachable
- Native `onStartCommand` calls `moveOverlay` once more at the end, overwriting the position set
  from the Dart side
- With `positionGravity != none`, **even a plain tap** schedules a snap-animation timer that
  fights programmatic moves over the same LayoutParams
- `dispatchGesture` coordinates are physical pixels, not dp
- A tap target underneath the ball is swallowed by our own overlay window (hence the snap toggle)
- Pick the target on `onTapUp`, not `onTapDown`: the latter swaps the widget tree while the finger
  is still down, and the following events land on the freshly built collapse gesture, closing the
  panel
- The system **hides third-party overlays on some settings screens** (anti-tapjacking) and there
  is no way around it; the accessibility service is unaffected, so recording continues meanwhile
