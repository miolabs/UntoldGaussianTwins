# UntoldGaussianTwins

Swap a mesh for its captured Gaussian-splat twin up close, with no popping, on top of
[UntoldEngine](https://github.com/miolabs/UntoldEngine).

The engine stays a renderer: it provides the mechanisms (a depth-only shrunk occluder shell
per mesh, a mesh colour fade, a per-entity splat opacity weight, the `gaussianAsset` link a
`.untold` scene carries, and a URL splat loader for mesh entities). This package is the
policy: when a twin loads, from what distance it swaps, how fast it fades, and how it comes
back.

## Setup

```swift
// Package.swift
.package(url: "https://github.com/miolabs/UntoldGaussianTwins.git", branch: "main")
```

```swift
import UntoldGaussianTwins

// Once at start-up, after the engine is initialised.
GaussianTwinSystem.shared.install()
```

The system ticks from the engine's update as an `EngineExtension` and cleans up after
destroyed entities.

## Linking a twin

From code, on any mesh entity:

```swift
setEntityGaussianTwin(
    entityId: chair,
    filename: "chair",               // chair.untoldgs (a .ply works too)
    withExtension: "untoldgs",
    options: GaussianTwinOptions(
        swapDistanceMeters: 4,       // 0 = always prefer the splat
        hysteresisMeters: 0.5,       // revert only beyond 4.5 m
        crossFadeDuration: 0.25,     // seconds, wall-clock
        occluderShrinkMeters: 0.02,  // the shell's margin behind the surface
        exposureOffsetEV: 0,         // on top of the capture exposure
        useRealWorldTint: false      // XR: tint by the real-world lighting estimate
    )
)
```

From a scene: a `.untold` file whose entity carries a `gaussianAsset` record flagged
`meshTwin` arrives with a `GaussianAssetLinkComponent`; the system adopts it automatically
(`adoptsSceneLinks`) with the record's margin, exposure offset and swap distance.

`removeEntityGaussianTwin(entityId:)` unlinks, drops the splat and shows the mesh.

## What happens

| State | On screen |
|---|---|
| `armed` | The mesh. The payload may already be resident from an earlier swap. |
| `loading` | Still the mesh; nothing changes until the payload is on the GPU. |
| `crossFading` | The mesh dithers out (`MeshFadeComponent`) while the splat's opacity ramps in, over `crossFadeDuration`. The occluder shell is on. |
| `swapped` | The splat. The mesh draws no colour (`MeshOccluderComponent.drawsColor = false`) but keeps writing depth as a shrunk shell, casting shadows, colliding and being picked. |
| `reverting` | The reverse fade when the camera leaves `swapDistanceMeters + hysteresisMeters`. Ends `armed`; the payload stays resident so the next swap is instant. |

Notes:

- Distance is measured from the camera to the entity's bounds centre.
- Each frame's fade step is capped at 100 ms, so the fade lasts `crossFadeDuration` at any
  refresh rate above 10 Hz.
- A batched mesh leaves its batch group when the swap starts and re-joins after reverting; the
  group is rebuilt over a few frames.
- Where splats cannot be drawn (the iOS simulator has no splat pipelines) twins stay armed.
- Soft objects differ from their mesh by centimetres: raise `occluderShrinkMeters` until the
  front of the capture stops clipping. `GaussianDebugOptions.shared.disableOccluderShells`
  turns the shells off for bisecting.

## Development

The package pins the engine fork's `develop` branch until the engine features ship in an
upstream release. To build against a local engine checkout:

```bash
swift package edit UntoldEngine --path ../../Untold/UntoldEngine
swift test
swift package unedit UntoldEngine
```
