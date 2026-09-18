# flutter-overlay-demo

[繁體中文](README.md) · **English**

A Flutter spike for an Android floating ball (AssistiveTouch-like). Personal use, not a product.

The ball is draggable and snaps to the nearest edge (toggleable); tapping it opens a menu with:
set tap target, start/stop auto tap (300ms interval), screenshot, back to app. Whatever the
overlay does is reported back to the host app and listed there. Theme and locale follow the
system (light/dark, Chinese/English); colors follow a blue theme reused from another project.

**Android only** — iOS has no public API for drawing on top of other apps.

## Two independent permissions

| Permission | Used for | How it is granted |
|---|---|---|
| `SYSTEM_ALERT_WINDOW` | the overlay window itself | system settings page, **no runtime dialog** |
| Accessibility service | simulated taps / screenshots | Settings → Accessibility, manually |

## Build

```bash
fvm flutter pub get
fvm flutter build apk --debug
```

## Locally patched third-party packages

Two packages are vendored with a fix (`packages/`, wired through `dependency_overrides`).
Both bugs share a cause: **upstream assumes it is only ever registered against one engine**,
while this app has two (the host app and the overlay).

### `flutter_overlay_window` (copy of 0.5.0)

`WindowSetup.messenger` is a static field, yet it is assigned in `onAttachedToEngine`. The
plugin registers against both engines and the later one (the overlay) wins, so `OverlayService`
forwarded the overlay's `shareData()` **straight back to the overlay** and the host app never
received anything. The assignment moved to `onAttachedToActivity` — only the host engine ever
gets an Activity, which is the one place the two can be told apart.

### `flutter_accessibility_service` (copy of 1.2.0, MIT, by Iheb Briki)

**One line changed**:

`AccessibilityListener.onServiceConnected()` called `Objects.requireNonNull` on a cached engine
that is only ever created in `onAttachedToActivity`. When the process is started *by* the
accessibility binding (after an install, after a reboot), no Activity has run yet and the cache
is empty → NPE → process crash → rebind → crash again, a crash loop. The service therefore
never actually connected, and `dispatchGesture` handles "service not connected" by **silently
returning false with no log at all**, so nothing about this was visible from the outside.

The fix skips that overlay feature (unused here) when there is no engine.

## Known issues

**When the window changes size or position, the picture lags the parameters by ~280ms.**
Measured: the LayoutParams reported by `getOverlayPosition()` are final within 1ms, but the
window on screen takes ~283ms to catch up — the move happens at the surface/compositor layer,
out of Dart's reach.

Three mitigations are in place. **All of them mask the symptom; none fixes the cause**:

1. Draw nothing during the transition (`_BallMode.switching`)
2. `await endOfFrame` before touching the window, so what the system stretches is a blank
   frame rather than the ball
3. Reveal only after the geometry has landed (`kCollapseRevealDelay` 300ms /
   `kExpandRevealDelay` 200ms); both values were measured frame by frame

The two edges used to feel different for the same reason: expanding always anchors the window
at (0,0), so a ball on the left needs no horizontal move while one on the right travels almost
a full screen width. Item 3 evens them out.

## Traps hit along the way (all documented in `lib/main.dart` comments)

- `showOverlay` takes width/height in px, while `resizeOverlay` and `startPosition` take dp
- `resizeOverlay` has no MATCH_PARENT sentinel for height (upstream's condition is always true),
  so it only accepts a real dp value
- Align the window with `topLeft`; centered gravity measures against the parent frame with the
  system bars removed, which differs from `display.size` by one inset
- `closeOverlay` does not rebuild the isolate (the engine is cached), so `initState` never re-runs
- `closeOverlay` also gives the overlay's Dart side **no signal at all** — it only tears down the
  native view. Timers there must check `isActive()` themselves, or they keep running after the
  window is gone, with the stop button no longer reachable
- `performGlobalAction` only checks "enabled in settings", not "actually bound", and returns
  `true` unconditionally (the vendored copy adds the connected check)
- Native `onStartCommand` calls `moveOverlay` once more at the end, overwriting the position set
  from the Dart side
- With `positionGravity != none`, **even a plain tap** schedules a snap-animation timer that
  fights programmatic moves over the same LayoutParams
- `dispatchGesture` coordinates are physical pixels, not dp
- A tap target underneath the ball is swallowed by our own overlay window (hence the snap toggle)
- Pick the target on `onTapUp`, not `onTapDown`: the latter swaps the widget tree while the
  finger is still down, and the following events land on the freshly built collapse gesture,
  closing the panel
