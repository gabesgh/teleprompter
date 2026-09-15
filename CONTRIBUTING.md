# Contributing

Bug reports and pull requests are welcome.

## Building

Open `Teleprompter.xcodeproj` in Xcode 15 or newer and press Run. No signing
setup is needed. The project is configured for ad-hoc signing.

`./build.sh --open` does the same from the terminal and drops the result in `dist/`.

## Project structure

The Xcode project is generated from `project.yml` with
[xcodegen](https://github.com/yonaskolb/XcodeGen). If you add or rename files,
either add them through Xcode or run `xcodegen` to regenerate the project.
Both are fine, just commit the resulting `.xcodeproj` alongside your change.

Everything that matters lives in `Teleprompter/`:

- `PrompterModel.swift`: state, the scroll engine, import, window features, keyboard shortcuts, persistence
- `ContentView.swift`: the main window (scrolling text, guide line, drag & drop)
- `ControlsOverlay.swift`: toolbars, transport, sliders, progress track
- `ScriptEditorView.swift`: the editor window
- `AppCommands.swift`: menu bar

## Releasing

Tag a commit on `main` with a version and push it:

```sh
git tag v1.1.0
git push origin v1.1.0
```

The Release workflow builds a universal binary, zips it, and publishes a GitHub
Release with the download attached.
