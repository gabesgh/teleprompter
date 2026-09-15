# Teleprompter for Mac

A free, native macOS teleprompter. Load a script, set the speed and text size, and read.
Goes full screen for recording, or shrinks to a small always-on-top window that floats
over Zoom, OBS, or your browser, and can hide itself from screen recordings.

## Download

**[Download the latest release →](../../releases/latest)** (`Teleprompter-x.y.z.zip`)

1. Unzip it and drag **Teleprompter.app** into your Applications folder.
2. On first launch macOS will say it *"cannot verify that this app is free of malware"*.
   That's because it isn't notarized with Apple (which costs $99/year), not because
   anything is wrong. Open **System Settings → Privacy & Security**, scroll down, and click
   **Open Anyway**. You only have to do this once.

   Prefer the terminal? `xattr -dr com.apple.quarantine /Applications/Teleprompter.app` does the same thing.

Requires macOS 14 Sonoma or newer. Works on Apple Silicon and Intel Macs.
The source is open (MIT) and every release is built by GitHub Actions from this repo,
so you can check exactly what you're running.

## Using it

**Load a script.** Drop a `.txt`, `.md`, `.rtf` or `.docx` file onto the window, press
⌘O to pick a file, ⇧⌘V to paste, or ⌘E to type it in. Your script and settings are
remembered between launches.

**Read.** Press Space (or click the text) to start scrolling. The orange line is your
reading guide; keep your eyes there. Speed and text size are the two sliders at the
bottom. Speed is tied to text size, so making the text bigger doesn't make you read faster.

**Record.** Press `F` for full screen. Or shrink the window down small: the toolbars
disappear, leaving just the text, a play/pause button and the progress bar on the right
edge. Turn on **Float on Top** (pin icon, ⌘T) to keep it above whatever you're recording
with, and **Hide from Screen Capture** (eye icon, ⇧⌘H) so it never shows up in your
recording or screen share.

### Keyboard

| Action | Key | Menu |
|---|---|---|
| Play / pause | `Space`, or click the text | Playback ▸ Play / Pause (⌘↩) |
| Speed up / slow down | `↑` / `↓` | Playback ▸ Faster / Slower (⌘↑ / ⌘↓) |
| Jump back / forward (¼ screen) | `←` / `→` | Playback ▸ Jump (⌘← / ⌘→) |
| Restart from top | `R` or `Home` | Playback ▸ Restart (⌘R) |
| Bigger / smaller text | `+` / `-` | Display ▸ Bigger / Smaller Text (⌘= / ⌘-) |
| Full screen | `F` (Esc exits) | Display ▸ Toggle Full Screen (⇧⌘F) |
| Reading guide on/off | `G` | Display ▸ Reading Guide (⇧⌘G) |
| Mirror text (beam-splitter glass) | `M` | Display ▸ Mirror Text (⇧⌘M) |
| Float on top of other windows |  | Display ▸ Float on Top (⌘T) |
| Hide from screen recording / sharing |  | Display ▸ Hide from Screen Capture (⇧⌘H) |
| Import a file |  | Script ▸ Import… (⌘O) |
| Paste from clipboard |  | Script ▸ Paste from Clipboard (⇧⌘V) |
| Type / edit the script |  | Script ▸ Edit Script… (⌘E) |

The progress track on the right edge is always visible. Drag it to jump anywhere.
Controls fade out while playing and come back when you move the mouse.

There's a sample script in [`samples/demo.txt`](samples/demo.txt) to try things out with.

## Building from source

Open `Teleprompter.xcodeproj` in Xcode 15 or newer and press Run. No signing setup
needed. Or from the terminal:

```sh
./build.sh --open      # builds dist/Teleprompter.app and launches it
./build.sh --install   # builds and copies it to /Applications
```

The Xcode project is generated from `project.yml` with
[xcodegen](https://github.com/yonaskolb/XcodeGen); the generated project is committed
so you don't need xcodegen unless you change `project.yml`. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the layout and how releases are cut.

## How it works

- **SwiftUI + AppKit, macOS 14+.** SwiftUI for the UI; AppKit for what SwiftUI doesn't
  expose: window level (float on top), `sharingType` (hide from capture), full screen,
  the open panel, and a key-event monitor.
- **Scrolling** is a `CADisplayLink` advancing one `offset` value each frame, applied to
  the text with `.offset(y:)`. It's delta-time based, so it's smooth at any refresh rate
  and doesn't drift.
- **Speed is relative to font size** (`points/sec = speed × fontSize × 0.5`).
- **Single-key shortcuts** (space, arrows, letters) go through a local `NSEvent` monitor
  that steps aside whenever a text field has focus, so typing in the editor never
  triggers them. ⌘-shortcuts live in the menu bar as usual.
- **State** is one `@Observable` model. Persisted properties are watched with
  `withObservationTracking` and written to `UserDefaults` on change.

## License

[MIT](LICENSE)
