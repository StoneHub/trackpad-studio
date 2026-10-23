# Trackpad Studio

**Your Mac trackpad is a pressure-aware multi-touch canvas. This app proves it.**

Draw with your fingers at absolute trackpad positions, feel force change your ink,
zoom and pan in a single two-finger gesture, and explore everything the trackpad
can secretly do — including weighing things (really).

**Website:** [canvas.zaynjarvis.com](https://canvas.zaynjarvis.com) ·
**Support:** [Buy me a coffee ☕](https://buymeacoffee.com/zaynjarvis?status=1)

![The board — draw directly with your fingers](docs/assets/board.png)

## Why a native Mac app

Browsers can't see trackpad touches at all — to the web platform a trackpad is
just a relative mouse (pinch arrives as ctrl+wheel, force only in Safari during
clicks, zero per-finger data). Absolute-position finger drawing needs AppKit's
`NSTouch` API, Force Touch pressure events, and (optionally) the private
MultitouchSupport framework for per-finger contact size.

## Features

- **Draw mode** — the system cursor freezes and hides during strokes; a light
  touch moves the pointer to the controls. The visible Draw / Pointer selector switches to normal pointing (`Esc` also works), and the app
  guarantees your cursor is restored on focus loss, view teardown, and quit.
- **Absolute finger drawing** — the on-screen corner brackets mirror the
  physical pad; anything capacitive can draw.
- **Force-aware ink** — light touch is a hovering cursor, a click draws, and
  Force Touch pressure drives stroke width.
- **Unified pinch + pan** — computed from raw two-finger touches (centroid pan,
  distance-ratio zoom anchored at the centroid), bypassing macOS gesture
  exclusivity: you can zoom while panning in one continuous gesture.
- **Three-finger force draw** — three-finger drag executes the current tool at
  full force; the leftmost finger is the pen and stays the pen until release.
- **Tools 1–5** — pen, line, rectangle, ellipse, arrow in an always-visible left
  toolbar with active highlight. `T` drops one-shot text that keeps a constant
  on-screen size at any zoom, then hands the pen back.
- **Guided tutorial** (`⌘T` or the `?` button) — 8 trackpad capabilities as
  tutorial cards with live ✓ discovery, plus a weight-estimate card that turns
  the pad into a rough gram scale via capacitive contact size.
- **Palm-safe** — resting thumbs/palms are filtered out of every gesture and
  rendered as faint ghost rings.

![The guided tutorial panel](docs/assets/tutorial.png)

## Install

**Download** — grab [TrackpadStudio.dmg](https://github.com/ZaynJarvis/trackpad-studio/releases/latest/download/TrackpadStudio.dmg),
drag the app to Applications, then clear the quarantine flag once (the app is
open source but not notarized with a paid Apple Developer ID):

```bash
xattr -cr /Applications/TrackpadStudio.app
```

**Or build from source** (macOS 13+, Swift 5.9+ / Xcode command line tools):

```bash
git clone https://github.com/ZaynJarvis/trackpad-studio
cd trackpad-studio
./make-app.sh          # → TrackpadStudio.app (or: swift run TrackpadStudio)
```

## Controls

The sidebar has labeled buttons for **Pen, Eraser, Line, Rectangle, Ellipse,
Arrow, Text, Undo, and Clear canvas**, plus a **Draw / Pointer** selector.
No shortcuts are required.

- **Draw:** press and slide a finger to draw at its absolute trackpad position.
  A light touch moves the normal pointer so you can reach the sidebar; the
  pointer freezes only while drawing or using a two/three-finger gesture.
- **Pointer:** use the normal cursor without drawing. Click **Draw** or choose
  any drawing tool to resume drawing.
- **Eraser:** press and sweep to remove whole strokes or objects. The orange
  ring shows its reach. Each erase gesture is one undo step.
- **Undo:** restores the last drawing, erase, or clear operation.
- **Clear canvas:** clears everything; Undo brings it back.
- **Text:** places an editable text field at the last drawing position. Return
  commits the text; Escape cancels editing.
- Two fingers pan and zoom in Draw; three fingers draw/erase without a click.
- A conventional mouse can also draw or erase by dragging in Draw mode.

Optional shortcuts: **Esc** toggles Draw/Pointer, **1–5** select the original
five tools, **E** selects Eraser, **T** places text, **⌘Z** undoes, **⌘Delete**
clears. **[ / ]** adjust the firm-touch threshold. Existing **⌘G** AI redraw
is unchanged and is not needed for drawing.

### Regression checks

```bash
swiftc Sources/TrackpadStudio/BoardModel.swift Tests/BoardModelChecks.swift -o /tmp/board-model-checks
/tmp/board-model-checks
```

These check fast eraser sweeps, shape outlines, arrowheads, cancellation,
undoable clearing and erasing, replacement history, and zoom/pan coordinates.

## Weight scale & per-finger detail

Per-finger contact size/ellipse (and therefore the weight estimate and
click-free force drawing) uses the private `MultitouchSupport.framework`,
loaded at runtime with a graceful fallback. On modern macOS the data stream
requires **Input Monitoring** permission for the launching app (System
Settings → Privacy & Security → Input Monitoring). Everything else works
without it. The gram scale is a calibratable party trick, not a measuring
instrument.

## Architecture

Plain Swift Package Manager executable — no Xcode project, no dependencies.

```
Sources/TrackpadStudio/
  TrackpadCore.swift      shared input model + touch-capture view
  MultitouchBridge.swift  private-framework reader (dlopen, safe fallback)
  BoardTab.swift/.Model   the canvas: modes, gestures, tools, rendering
  CapabilityTab.swift     the guided tutorial / live instrument panel
  AppShell.swift          window, menu, tutorial panel, --snapshot mode
Sources/CMultitouchShim/  C struct layout for the private framework
```

`TrackpadStudio --snapshot <dir>` renders marketing screenshots of its own
windows (no screen-recording permission needed).

## License

[MIT](LICENSE) © Zayn Jarvis

If this made your trackpad more fun, consider
[buying me a coffee ☕](https://buymeacoffee.com/zaynjarvis?status=1).
