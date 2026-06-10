# HeightMeasure (Triangulation-based Height Measurement)

A minimal iOS AR prototype that measures the height (vertical distance from the ground) of objects above ground level — such as a second-floor balcony or window — by holding up the phone while standing on the ground. It does not use LiDAR; it relies solely on ARKit world tracking (VIO) and a gravity-aligned pose (`worldAlignment = .gravity`).

## How it measures

Aim the on-screen reticle and capture two points in order using the bottom measure button.

1. **① Base of the wall (the ground directly below the target)** — raycast against the infinite extension of the detected horizontal plane (`.existingPlaneInfinite`, falling back to `.estimatedPlane` if empty) to fix the base point `B`. Assumes **flat, level ground**, so the far wall base can be captured while holding the phone nearly upright.
2. **② Target (the point whose height you want)** — compute height `H` from the camera position `C` and forward vector `f` at that instant.

Formula (§5.2):

```
d    = sqrt((Cx - Bx)^2 + (Cz - Bz)^2)   // horizontal distance to base
f_h  = sqrt(fx^2 + fz^2)                  // horizontal component of forward vector
H    = (Cy - By) + d * (fy / f_h)         // height above ground (m)
```

Valid conditions: `f_h >= 0.05` (not aimed too close to straight up) and `fy > 0` (target is above the camera). Otherwise no measurement is taken and an error is shown.

## Features

- Multiple measurements per session, accumulated in a numbered list at the bottom (newest on top).
- Redo (discard the last base point while in `.waitingTarget`).
- Clear (remove all results and the AR markers/vertical lines, reset numbering).
- Results are not persisted (discarded when the app exits).

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
