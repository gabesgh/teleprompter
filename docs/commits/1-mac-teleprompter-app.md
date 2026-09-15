# 1st commit: mac teleprompter app, delta-time scroll engine, script import from txt/md/rtf/docx, float on top, hide from screen capture, reading guide and mirror mode, compact always-on-top window, script editor window, single-key shortcut monitor, xcodegen project and build script, app icon generator, ci and tag-triggered release workflows, readme and contributing docs

## Context
A free, native macOS teleprompter with no account and no subscription. The goal is
a window you can read from while recording: full screen for a camera, or a small
always-on-top window that floats over Zoom or OBS and hides itself from screen
capture. Everything ships from GitHub Actions so a release is reproducible from
the tagged source.

## Changes
- [PrompterModel.swift](../../Teleprompter/PrompterModel.swift): one `@Observable`
  model holding script text, speed, font size, guide/mirror toggles, and playback
  state. The scroll engine is a `CADisplayLink` wrapper
  ([PrompterModel.swift:323](../../Teleprompter/PrompterModel.swift#L323)) that
  advances a single `offset` by delta time each frame. Speed is relative to font
  size ([PrompterModel.swift:43](../../Teleprompter/PrompterModel.swift#L43)).
  Import reads plain text directly and rich formats through `NSAttributedString`
  ([PrompterModel.swift:155](../../Teleprompter/PrompterModel.swift#L155)).
  Window features (float on top, `sharingType` for hide-from-capture at
  [PrompterModel.swift:222](../../Teleprompter/PrompterModel.swift#L222)) and a
  local `NSEvent` key monitor
  ([PrompterModel.swift:233](../../Teleprompter/PrompterModel.swift#L233)) live
  here too. Persisted properties are tracked with `withObservationTracking` and
  written to `UserDefaults`.
- [ContentView.swift](../../Teleprompter/ContentView.swift): the scrolling text,
  reading-guide line, drag and drop target, and empty-state prompt.
- [ControlsOverlay.swift](../../Teleprompter/ControlsOverlay.swift): top and
  bottom toolbars, transport, speed and size sliders, the always-visible progress
  track on the right edge, and the fade-out while playing.
- [ScriptEditorView.swift](../../Teleprompter/ScriptEditorView.swift): editor
  window for typing or editing the script in place.
- [AppCommands.swift](../../Teleprompter/AppCommands.swift): Playback, Display,
  and Script menus with the ⌘ shortcuts.
- [TeleprompterApp.swift](../../Teleprompter/TeleprompterApp.swift),
  [WindowAccessor.swift](../../Teleprompter/WindowAccessor.swift): app entry and
  the NSWindow bridge the model needs.
- [project.yml](../../project.yml) and the generated
  [Teleprompter.xcodeproj](../../Teleprompter.xcodeproj): xcodegen spec, ad-hoc
  signing, macOS 14 target, shared scheme.
- [build.sh](../../build.sh): `--open` and `--install` wrappers around
  `xcodebuild` for people who don't want to open Xcode.
- [tools/make-icon.swift](../../tools/make-icon.swift): generates the AppIcon
  set (checked in under `Teleprompter/Assets.xcassets`).
- [.github/workflows/ci.yml](../../.github/workflows/ci.yml): universal Release
  build on every push and PR.
- [.github/workflows/release.yml](../../.github/workflows/release.yml): on a
  `v*` tag, builds, zips, writes checksums, and creates the GitHub Release with
  [release-notes.md](../../.github/release-notes.md) as the body.
- [README.md](../../README.md), [CONTRIBUTING.md](../../CONTRIBUTING.md),
  [LICENSE](../../LICENSE), [samples/demo.txt](../../samples/demo.txt).

## Why
- `CADisplayLink` with delta time instead of a `Timer`: a timer drifts and
  stutters at 120 Hz. One offset value advanced per frame is smooth at any refresh
  rate and trivially pausable.
- Speed tied to font size: users expect "speed 3" to mean the same reading pace
  whether the text is 40pt or 80pt. Scaling points/sec by font size does that.
- Local `NSEvent` monitor for single-key shortcuts rather than SwiftUI
  `.keyboardShortcut`: SwiftUI can't bind bare Space or arrow keys without a
  modifier. The monitor steps aside when a text field has focus so the editor
  never triggers playback.
- `NSWindow.sharingType = .none` for hide-from-capture: this is the only public
  API that excludes a window from screen recording and screen share.
- Ad-hoc signing and no notarization: notarization needs a paid developer
  account. The README explains the one-time Gatekeeper override instead.
- Generated `.xcodeproj` is committed: contributors shouldn't need xcodegen to
  build.

## Files
| File | Change |
|---|---|
| .github/release-notes.md | Release body: install steps and Gatekeeper note |
| .github/workflows/ci.yml | Universal Release build on push/PR |
| .github/workflows/release.yml | Tag-triggered build, zip, checksum, GitHub Release |
| .gitignore | build/, dist/, xcuserdata, .DS_Store |
| CONTRIBUTING.md | Build, project layout, release process |
| LICENSE | MIT |
| README.md | Download, usage, keyboard table, how it works |
| Teleprompter.xcodeproj/** | Generated project, workspace, shared scheme |
| Teleprompter/AppCommands.swift | Menu bar commands |
| Teleprompter/Assets.xcassets/** | App icon set |
| Teleprompter/ContentView.swift | Main window content |
| Teleprompter/ControlsOverlay.swift | Toolbars, sliders, progress track |
| Teleprompter/Info.plist | Bundle metadata |
| Teleprompter/PrompterModel.swift | State, scroll engine, import, window features, shortcuts, persistence |
| Teleprompter/ScriptEditorView.swift | Script editor window |
| Teleprompter/TeleprompterApp.swift | App entry |
| Teleprompter/WindowAccessor.swift | NSWindow bridge |
| build.sh | Terminal build wrapper |
| project.yml | xcodegen spec |
| samples/demo.txt | Sample script |
| tools/make-icon.swift | Icon generator |
| docs/commits/1-mac-teleprompter-app.md | This file |

## Verification
- `xcodebuild -project Teleprompter.xcodeproj -scheme Teleprompter -configuration Release -destination 'platform=macOS' ONLY_ACTIVE_ARCH=NO ARCHS="arm64 x86_64" CODE_SIGN_IDENTITY=- build` succeeds (same invocation as CI). `lipo -info` on the binary reports both arm64 and x86_64.
- Manual: `./build.sh --open`, drop `samples/demo.txt` on the window, press Space
  and confirm smooth scrolling. Press ⌘T then ⇧⌘H and start a screen recording;
  the window should not appear in it.

## Rollback
`git revert` removes the whole app; there is no state outside the repo except
the `UserDefaults` domain for the bundle id, which is harmless to leave.
