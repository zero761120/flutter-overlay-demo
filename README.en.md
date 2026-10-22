# flutter-overlay-demo

[繁體中文](README.md) · **English**

A Flutter spike for an Android floating ball (AssistiveTouch-like). Personal use, not a product.

The ball is draggable and snaps to the nearest edge on release (toggleable); while dragging, an X
appears at the bottom — drop the ball on it (or fling it there) to close the whole app. Tapping
the ball opens a menu with:
set tap target, start/stop auto tap (300ms interval), screenshot, **solve MeowDoku**, **record a
flow**, clear recordings, back to app. Whatever the overlay does is reported back to the host app
and listed
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

## Drag to X to close

The feel follows the system's notification bubbles (AOSP WM Shell's `DismissView` +
`MagnetizedObject`):

- When a drag starts, an X fades in at the bottom centre (white ring, transparent inside)
- Once the finger is within 64dp of it, the ball springs into the centre carrying the finger's
  velocity, with a haptic tick, and the ring widens around it; leaving that radius springs the
  ball back to the finger
- Release on the X, or fling towards it (fast enough downwards, with the line of the fling
  crossing the X's row inside a band three X-widths wide centred on it): the ball shrinks away,
  then the overlay, its foreground
  notification and the host app (removed from recents too) are closed and the process ends. A
  recording in progress is saved first
- Released anywhere else (if snapping is on): the ball springs to the nearest edge, or to the far
  one if flung there fast enough

Springs and thresholds are taken from AOSP (android13): stick-in stiffness 1500 / critically
damped, spring-to-finger 12000 / 0.85, edge snap 700 / 0.85. AOSP's velocity thresholds are in
px/s; here they are converted to dp/s at the test device's density.

The accessibility service is **not** turned off (it would have to be re-enabled in Settings next
time). As long as it stays enabled, the system immediately brings up a new process to bind it:
that process has no Flutter engine and ignores every event while nobody is listening (see the
fixes below) — measured at about 28MB PSS.

The system caps non-touchable overlays at 0.8 opacity, so the X's white reads slightly grey.

**When automating tests**: start drags at least 42dp from the screen edge (see the back gesture
under "Known issues"). Also, `adb shell input motionevent` sends nothing while "holding still",
unlike a real finger that keeps reporting tiny moves, and AOSP's "don't stick when moving sideways
too fast" rule is only re-evaluated on the next move event — so "drag into the X and release" can
fail spuriously. Add one small move after the pause.

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

## Solving MeowDoku

The rules: an N×N board split into N colored regions; place one cat in every row, every column
and every region, and no two cats may touch — **diagonals included** (counting only up/down/
left/right would make that rule meaningless, since one cat per row and column already guarantees
it).

The game is drawn by the Godot engine: its accessibility tree is a single empty container with no
cells in it, so the only option is to read pixels:

1. Panel → "Solve MeowDoku". The overlay first clears itself to transparent, otherwise the panel
   would sit on top of the board and end up in the capture
2. The accessibility service's `takeScreenshot` (Android 11+) returns the pixels directly: **no
   MediaProjection consent dialog, nothing in the gallery, nothing written to disk**
3. Finding the board: plot "how many colored pixels per row / per column"; the board shows up as a
   run of equally sized, equally spaced plateaus. N is measured from the screen, so 8–12 cell
   levels all work
4. Reading regions: each cell is sampled at 8 points around its rim, white (X marks, cat faces) and
   black (cat fur) samples are dropped, and the rest vote — boards played halfway with X marks
   everywhere, and the game's pattern mode, both read fine
5. Row-by-row backtracking. **A second solution means the board was misread**: when one cell lands
   in a neighbouring region, the number of colors stays the same and the earlier checks cannot
   tell; measured on the level-10 board, 42 of the 162 single-cell misreads give a wrong answer if
   only the first solution is taken, and every one of those 42 has more than one solution
6. The window shrinks to a small card placed right below the board (above it if there is no
   room), on the same side as the ball; it can be dragged, and a tap turns it back into the ball

Verified on a real device (Android 15): a fresh 12×12 daily challenge, and level 1642 (10×10)
played down to its last cat in both normal and pattern mode — every answer matched the in-game
solution; the game's home screen correctly reports that no board was found.

The reader is tuned to this game's look (light background, white gaps, flat-colored cells); a
different theme or a different game is not guaranteed to work. When reading fails, the card says
why (no board, row/column count mismatch, region count mismatch, no solution, more than one
solution) instead of making up an answer.

**When testing**: reading the UI with uiautomator (mobile-mcp's element listing included) connects
a UiAutomation, and while it is connected Android **suspends every accessibility service** — the
settings screen still says "enabled", but the screenshot reports that the service is not ready.
mobile-mcp leaves `com.mobilenext.mobilecli.DeviceServer` running on the device for 30 minutes of
idle time; `adb shell kill` it and the service rebinds on its own within a second or two. Driving
the device with `adb shell input` + `adb exec-out screencap` avoids the problem altogether. To
check whether the service is bound, read Bound services in `dumpsys accessibility`: the list wraps
onto the next line, and grepping a single line misreads "bound" as "not bound".

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
door and leave the back one open; event payloads travel through an in-process queue rather
than a system broadcast, so no other app can passively receive them; and the solver's screenshot
lives in memory only until the board has been read — all that is kept is the region map and its
colors, and nothing is written to disk.

The author accepts no liability for how it is used (see `LICENSE`).

## License

This project is MIT (see `LICENSE`).

The two packages under `packages/` are **modified copies** of third-party code, originally by
Iheb Briki under the MIT license; each keeps its own `LICENSE` file intact. Every change is
marked with a `LOCAL PATCH` comment in the source; the what and why are in the next section.
The fixes address genuine upstream defects or limitations upstream does not handle; there are
also a few added features (a screenshot that returns pixels, drag to X to close, the native edge
snap, a "back to app" that matches the launcher), likewise listed in the next section.

The `flutter_accessibility_service` ones have been reported upstream:

- [#46](https://github.com/X-SLAYER/flutter_accessibility_service/issues/46) — the
  `onServiceConnected` crash loop
- [#47](https://github.com/X-SLAYER/flutter_accessibility_service/issues/47) — the five capture
  defects, plus two architectural findings where no fix is proposed

The two found later in this package (the `onStartCommand` crash, processing events with nobody
listening) have not been reported: neither issue above had a reply as of 2026-10-22, and upstream
has not pushed since 2026-06.

None of the `flutter_overlay_window` ones were reported at first: at the time, upstream's last
release was 2025-04, a year and a half earlier. Upstream picked up again in 2026-10 (1.0.0 / 1.0.1,
with another batch merged on main since). Compared against main (`e3c3549`) on 2026-10-22: the touch
slop drag threshold, sub-pixel dragging, drag to X (a simpler version), `getScreenSize`, drags no
longer ending as taps, and snapping only after a real drag are fixed or have an equivalent upstream;
the `onStartCommand` crash, message routing, the ball ending up off-screen after rotation, no
"resumed" on reopen, and the resize height condition are all still unfixed. This repo still uses
its modified copy of 0.5.0.

- [#205](https://github.com/X-SLAYER/flutter_overlay_window/issues/205) — the `onStartCommand`
  crash (the earlier reports #177 / #181 / #186 were closed, but the code was not changed)

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

**Screen size after rotation** — the overlay engine lives under a Service and has no Activity,
and Flutter's embedding only pushes the display size into an engine when it can find an Activity
(confirmed by disassembling `ViewUtils.calculateMaximumDisplayMetrics` in Flutter 3.38.10), so
the overlay's `display.size` stays at the orientation the engine was created in. Measured: created
in landscape and rotated back to portrait, the "snap right once the ball's centre passes half the
width" threshold became 487dp while portrait is only 417dp wide, so dragging right always snapped
back to the left. Added `getScreenSize` (`getRealMetrics`, the same meaning as `display.size`);
the Dart side asks for it at the start of every action that needs the size. The release snap has
since moved to native code, which reads the size itself; Dart now uses it for expand/collapse.

**Restart with a null intent after the process is killed** — `onStartCommand` returned
`START_STICKY` yet read the intent unconditionally. If the process died while the overlay was up,
the system restarted the service with a null intent and it threw an NPE. A restart could not have
brought the overlay back anyway (its position and size lived in the intent that is gone), so every
return is now `START_NOT_STICKY`, plus a null check.

**Added: `openHostApp` ("back to app" now sends its intent from native code)** — the app used to
build the intent with android_intent_plus: the action was the literal string `action_main` (the
plugin passes it through instead of mapping it to `ACTION_MAIN`), and the plugin always sets the
package whenever a component is given. With the Flutter template's `taskAffinity=""`, recents only
merges two tasks whose intents are `filterEquals`, and this one never matched the launcher's.
Measured: once the host app was closed with Back (the overlay keeps the process alive and the task
stays in recents), mixing the launcher icon and "back to app" left two overlay_demo cards in
recents (using only one of them never did). It now sends what the launcher sends: `Intent.makeMainActivity(component)`
(MAIN + LAUNCHER, component only, no package) plus `NEW_TASK | RESET_TASK_IF_NEEDED`, so the
system treats both as the same task and replaces the stale card. android_intent_plus is no longer
used and has been removed.

**Dart never sees "resumed" when the overlay is reopened** — the plugin only ever sends
`appIsResumed` on show, and Flutter's `LifecycleChannel` drops a state equal to the last one, so
the overlay's Dart side only got "resumed" on the first show. `main.dart` relies on it to reset
to the ball on reopen, and that reset never ran. Measured: close the overlay from the host app
while the solution card is up, reopen it, and the card is drawn squeezed into the ball's window
("OVERFLOWED"). Every show now sends inactive, then resumed. Not done as "paused" on close
instead: when the overlay is shown again right after closing, the previous onDestroy can run after
the new show (the comment on `_show` in `main.dart` records this ordering), which would leave a
visible overlay paused.

**A drag released as a tap** — the window follows the finger, so in the window's own coordinates
the pointer barely moves, and Flutter's tap slop (on Android, the platform touch slop) is only
exceeded on an event where the window happens to lag one step behind the finger. Measured with a slow drag inward from the left
edge: Flutter saw at most 13 logical px of movement, fired `onTap` on release and the panel
opened; the pre-patch build differed only in having one lagging event (26 px) in that drag — a
race, not a rule. Now, whenever the ball was dragged, Flutter gets a cancel instead of the up on
release; a plain tap is unaffected. That is also why the drag now starts at the platform touch
slop instead of upstream's 5 physical px (~2dp): otherwise a tap that wobbles more than 2dp would
count as a drag and the ball would become hard to open. Flutter takes its tap slop from the same
value, so both sides share one boundary — under it a tap for both, past it a drag for both
(measured on the Sony: a 40px wobble still opens the panel, 50px drags).

**Added: drag to X to close, and the release snap moved to native code** (not defects; see "Drag
to X to close"). Three implementation choices:

- The X is a separate native window, not drawn in Flutter: the plugin hosts a single Flutter
  window, so drawing it there would mean growing the ball's window to full screen mid-drag —
  exactly the ~280ms position lag, plus the coordinate origin jumping under the finger
- The X's window must be added **before** the ball's (windows of the same type stack in the order
  they are added). The first version added it when a drag started, and on video the ball was
  covered by the X for the few frames it took to slide in; now it is added as soon as the overlay
  appears and stays transparent until needed
- The snap used to move the window from Dart every 20ms through the method channel, out of step
  with the display: measured frame by frame on video, about half the frames did not move at all
  (per-frame steps 76, 0, 0, 52, 31, 0, 0, 0, 24, …). It is now a native spring driven by
  Choreographer. For the release snap Dart keeps only the toggle (`setSnapToEdge`) and "is the
  window the ball right now" (`setBallMode` — the solution card is draggable too, but neither
  snaps nor gets an X). Collapsing still places the ball at the edge from Dart, in one move rather
  than an animation

### `flutter_accessibility_service` (copy of 1.2.0)

Eleven defects, all found by measuring on a real device:

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
| Every event processed even with nobody listening | the system keeps an enabled service bound and the process resident; even the status-bar clock updating cost a tree walk on the main thread, a shared-prefs write and a broadcast |
| `onStartCommand` returned `START_STICKY` and read the intent unconditionally | the plugin delivers commands via `startService`, leaving the service start-requested; once the process is killed (swiped from recents, reclaimed for memory) the system restarts it with a null intent → NPE, again a few seconds later → "keeps stopping" |
| `onServiceConnected` called `requireNonNull` on an uncached engine | guaranteed NPE when the process is started by the service → crash loop → the service never connects |

The last one was the hardest to find: the system settings screen still lists the service as
enabled, but it never actually connected, and `dispatchGesture` handles that by **silently
returning false with no log at all**. It took a log line added in the native code to see both the
`source=null` behaviour and the crash loop.

The `onStartCommand` one is the "accessibility suddenly stopped working" that actually happened:
`adb logcat -b crash` still held two NPEs a few seconds apart. To reproduce: `adb shell run-as
com.louis.overlay_demo am startservice --user 0 -n <service component>` puts the service in the
started state (without `--user 0` it is refused), then kill the process with `run-as … kill -9`.

One feature upstream does not have is also **added** (not a defect): `takeScreenshot`, which
returns the RGBA pixels directly. Upstream only offers `GLOBAL_ACTION_TAKE_SCREENSHOT`, which drops
a file into the gallery and shows the system screenshot UI, so the app cannot read back what it
just captured. Failures are not swallowed but mapped to `NO_ACCESS` / `TOO_FREQUENT` /
`SECURE_WINDOW` / `NOT_CONNECTED` / `UNSUPPORTED`, so the caller can say something actionable.
The service XML has to declare `canTakeScreenshot`.

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

**Window animations are still occasionally uneven at 120Hz**: sticking to the X, the edge snap and
dragging all move a small window with `updateViewLayout`, one call per frame. Per-frame steps on
video still vary (e.g. 84, 34, 52, 0) — presumably because the cross-process position update does
not always land on the same frame, though it may just be sampling aliasing in the recording;
**which of the two was not determined**. The system's bubbles are perfectly smooth because they
move views inside one large window and narrow its touchable region with a hidden API, which
ordinary apps cannot use.

**The recorder's tree dedup can skip a screen**: the fingerprint is only
`packageName + child count + first 8 text fragments`, so two visually different screens that
happen to match on those are treated as "unchanged" and the tree is skipped, leaving only the
event itself.

**Rotating while the panel is open does not re-lay it out right away**: the screen size is fetched
at the start of each action (the overlay's Dart side gets no rotation notice), so the new size
only takes effect on the next action.

**With gesture navigation, a drag that starts at the screen edge can be taken by the system back
gesture**: when the ball rests on an edge and the touch lands in the outermost strip, the system
treats it as a back gesture and the overlay only receives a cancel — the ball does not move
(measured: starting 24dp from the edge works only some of the time, 42dp always works). Starting
the drag from the inner side of the ball is fine. If the system takes over mid-drag, the cancel
snaps the ball back to the edge as usual.

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
- The overlay's `display.size` does not follow rotation (its engine has no Activity); ask the
  native side instead
- Window sizes are dp converted to whole pixels, and rounding can leave a fraction of a pixel less
  than computed: content with a hard-coded size then overflows, so let it fill the remaining
  space; a `Border` also eats into the content area and has to be counted in the size
