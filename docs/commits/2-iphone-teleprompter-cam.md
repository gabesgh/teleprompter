# 2nd commit: iphone teleprompter cam app, draggable pinch-to-zoom camera window, lens switching 0.5x to 5x, in-app 1080p/4k recording to photos, horizon-level rotation, shared prompter engine, ios simulator ci build, readme and contributing updates

## Context
The Mac app solves reading while recording on a desktop. On a phone the problem
is different: the good cameras are on the back, and the screen faces the wrong
way. On a foldable opened flat the cover screen and the rear cameras face the
same direction, so a prompter that fills that screen and records with the rear
lenses gives you both at once. This adds `TeleprompterCam`, an iOS target in the
same project, built around that one trick.

## Changes
- [PrompterEngine.swift](../../TeleprompterCam/PrompterEngine.swift): the Mac
  scroll engine and script handling with the AppKit window code removed. Same
  speed-to-font-size formula, same delta-time `CADisplayLink` loop.
- [CameraController.swift](../../TeleprompterCam/CameraController.swift):
  `AVCaptureSession` with `AVCaptureMovieFileOutput`
  ([CameraController.swift:45](../../TeleprompterCam/CameraController.swift#L45)).
  Picks the best virtual multi-lens device available
  ([CameraController.swift:139](../../TeleprompterCam/CameraController.swift#L139))
  and reads its `virtualDeviceSwitchOverVideoZoomFactors`
  ([CameraController.swift:153](../../TeleprompterCam/CameraController.swift#L153))
  so the 0.5x/1x/2x/5x buttons land on real lens switch-over points rather than
  digital zoom. An `AVCaptureDevice.RotationCoordinator`
  ([CameraController.swift:249](../../TeleprompterCam/CameraController.swift#L249))
  keeps the preview and the recording level with the horizon. 1080p or 4K preset
  ([CameraController.swift:18](../../TeleprompterCam/CameraController.swift#L18)).
  Finished clips are saved through `PHPhotoLibrary` with add-only permission
  ([CameraController.swift:288](../../TeleprompterCam/CameraController.swift#L288)).
- [CameraPreview.swift](../../TeleprompterCam/CameraPreview.swift):
  `UIViewRepresentable` wrapper around `AVCaptureVideoPreviewLayer`.
- [CameraWindow.swift](../../TeleprompterCam/CameraWindow.swift): the small
  live preview that sits in a corner. Drag snaps to the nearest corner, pinch
  resizes, double-tap toggles a larger size. Lens buttons render under it.
- [ContentView.swift](../../TeleprompterCam/ContentView.swift): full-screen
  prompter with the camera window overlaid; tap the text to hide controls; keeps
  the screen awake while open.
- [ControlsOverlay.swift](../../TeleprompterCam/ControlsOverlay.swift),
  [Sheets.swift](../../TeleprompterCam/Sheets.swift): record button and timer,
  speed and size steppers, guide and mirror toggles, import from Files, paste,
  and in-app editor.
- [TeleprompterCamApp.swift](../../TeleprompterCam/TeleprompterCamApp.swift),
  [Info.plist](../../TeleprompterCam/Info.plist): app entry, camera, microphone,
  and Photos usage strings.
- [project.yml](../../project.yml) and the regenerated
  [Teleprompter.xcodeproj](../../Teleprompter.xcodeproj): second target and
  shared `TeleprompterCam` scheme.
- [tools/make-icon.swift](../../tools/make-icon.swift): also emits the iOS
  1024px icon.
- [.github/workflows/ci.yml](../../.github/workflows/ci.yml): `build-ios` job
  compiles the target for the iOS Simulator with signing disabled.
- [README.md](../../README.md): "iPhone app" section.
  [CONTRIBUTING.md](../../CONTRIBUTING.md): two-target layout and the
  signing-team note.

## Why
- Virtual multi-lens device instead of picking a physical camera per button:
  the virtual device handles the lens hand-off itself and exposes the exact zoom
  factors where it switches, so "2x" is the telephoto, not a crop of the wide.
- `RotationCoordinator` rather than reading `UIDevice.orientation`: it's the
  API Apple added for exactly this and it works while the interface is locked to
  one orientation, which the prompter is.
- `AVCaptureMovieFileOutput` over `AVAssetWriter`: no custom encoding pipeline
  needed for a straight 1080p/4K recording with audio, and it handles rotation
  metadata.
- Engine duplicated into `PrompterEngine.swift` rather than shared via a
  package: the two targets diverge on window handling and inputs, and a Swift
  package for ~200 lines adds more friction than it removes right now.
- Not on the App Store: the app needs no server or account, and sideloading
  with a free Apple ID is enough for the people this is for.

## Files
| File | Change |
|---|---|
| .github/workflows/ci.yml | Add iOS Simulator build job |
| CONTRIBUTING.md | Two-target layout, signing note, iPhone file list |
| README.md | iPhone app section |
| Teleprompter.xcodeproj/project.pbxproj | Regenerated with TeleprompterCam target |
| Teleprompter.xcodeproj/xcshareddata/xcschemes/TeleprompterCam.xcscheme | Shared scheme |
| TeleprompterCam/Assets.xcassets/** | iOS app icon |
| TeleprompterCam/CameraController.swift | Capture session, lens switching, rotation, recording, Photos |
| TeleprompterCam/CameraPreview.swift | Preview layer wrapper |
| TeleprompterCam/CameraWindow.swift | Draggable/pinchable preview and lens buttons |
| TeleprompterCam/ContentView.swift | Full-screen prompter with camera overlay |
| TeleprompterCam/ControlsOverlay.swift | Record, transport, steppers, toggles |
| TeleprompterCam/Info.plist | Bundle metadata and usage strings |
| TeleprompterCam/PrompterEngine.swift | Scroll engine and script handling |
| TeleprompterCam/Sheets.swift | Import, paste, editor sheets |
| TeleprompterCam/TeleprompterCamApp.swift | App entry |
| project.yml | TeleprompterCam target |
| tools/make-icon.swift | iOS icon output |
| docs/commits/2-iphone-teleprompter-cam.md | This file |

## Verification
- `xcodebuild -project Teleprompter.xcodeproj -scheme TeleprompterCam -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` succeeds (same invocation as the CI `build-ios` job).
- The Mac target still builds universal with the CI invocation after the
  project regeneration.
- On device: set a team, run on an iPhone, confirm the lens buttons switch
  without a visible zoom jump, record a 4K clip in landscape and portrait and
  check both are level in Photos.

## Rollback
`git revert` removes the iOS target and restores the single-target project and
docs. Recordings already saved to Photos are unaffected.
