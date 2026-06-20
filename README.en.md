# HeightMeasure (Triangulation-based Height Measurement)

A minimal iOS AR prototype that measures the height (vertical distance from the ground) of objects above ground level — such as a second-floor balcony or window — by holding up the phone while standing on the ground. It does not use LiDAR; it relies solely on ARKit world tracking (VIO) and a gravity-aligned pose (`worldAlignment = .gravity`).

## How it measures

Aim the on-screen reticle and capture two points in order using the bottom measure button.

1. **① Base of the wall (the ground directly below the target)** — raycast to a horizontal plane to fix the base point `B`. Accuracy-first order: `.existingPlaneGeometry` (the actually detected floor) → `.estimatedPlane` → `.existingPlaneInfinite` (infinite extension). Indoor/near targets land accurately; a far outdoor base is still captured via the infinite extension.
2. **② Target (the point whose height you want)** — compute height `H` from the camera position `C` and forward vector `f` at that instant.

Formula (§5.2):

```
d    = sqrt((Cx - Bx)^2 + (Cz - Bz)^2)   // horizontal distance to base
f_h  = sqrt(fx^2 + fz^2)                  // horizontal component of forward vector
H    = (Cy - By) + d * (fy / f_h)         // height above ground (m)
```

Valid conditions: `f_h >= 0.05` (not aimed too close to straight up) and `fy > 0` (target is above the camera). Otherwise no measurement is taken and an error is shown.

## Features

- **Start-of-measurement guide popup**: when entering height or window mode, an illustrated popup explains where to stand (step back so the ground and target are both in frame / face the window head-on). Dismiss by tapping the background or "はじめる" (Start).
- **Single measurement**: one measurement at a time; re-measuring replaces the previous one. The confirmed height is always shown as a pill (white capsule, black text) at the midpoint of the line.
- **Surface-conforming reticle**: an Apple Measure-style reticle (a white ring in AR space) tilts to lie on the surface it hits — flat on floors, upright on walls. The base point (①) only enables the measure button on a horizontal floor, preventing accidental selection of a wall.
- **Live guide**: after the base is set, while aiming at the target, a dotted line from the ground to the reticle, a live height value (cm/m), and an extension line are shown in real time.
- **Capture → save/share (3 steps)**: ① measure → ② capture mode (a framing guide turns green ✓ once the ground and endpoint are in frame, then shutter) → ③ preview to save (camera roll) or share. The height value is composited onto the photo, so ground, target, vertical line, and number all fit in one shot.
- Redo (discard the last base point while in `.waitingTarget`).
- Clear (remove all results and the AR markers/vertical lines, reset numbering).
- Measurements are not persisted (discarded when the app exits; saved photos remain in the camera roll).
- UI follows Apple HIG (material backgrounds, SF Symbols, capsule buttons).

## Requirements

| Item | Value |
|---|---|
| Platform | iOS (iPhone only) |
| Minimum OS | iOS 17.0 |
| Language / UI | Swift / SwiftUI |
| AR | ARKit + RealityKit (`ARView` wrapped via `UIViewRepresentable`) |
| Orientation | Portrait only |

## Project structure

| File | Responsibility |
|---|---|
| `HeightMeasure/HeightMeasureApp.swift` | App entry point |
| `HeightMeasure/ContentView.swift` | ZStack of AR view and overlay |
| `HeightMeasure/ARViewContainer.swift` | Creates `ARView` and configures the session |
| `HeightMeasure/MeasureViewModel.swift` | State, measurement logic, `ARSessionDelegate` |
| `HeightMeasure/HeightCalculator.swift` | Pure height function (§5.3, no ARKit dependency) |
| `HeightMeasure/Measurement.swift` | Measurement result model |
| `HeightMeasure/OverlayView.swift` | Reticle, banner, result list, three buttons |
| `HeightMeasure/MeasureState.swift` | State enum and display strings |

## Build

```sh
xcodebuild build -scheme HeightMeasure \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

> Note: on environments where the installed iOS simulator runtime does not match the version bundled with Xcode, `-destination` resolution can fail. In that case you can verify compilation via an explicit SDK:
> `xcodebuild -target HeightMeasure -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO`

## Test

`HeightCalculator` is a pure function with no ARKit/RealityKit dependency, so it can be verified natively on macOS without a simulator (all 5 cases, including the 3 from §10-1):

```sh
swift test
```

On environments with an available simulator, the Xcode logic tests can also be used:

```sh
xcodebuild test -scheme HeightMeasure \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```
