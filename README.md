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
// Package.swift (once the package is published under miolabs)
.package(url: "https://github.com/miolabs/UntoldGaussianTwins.git", branch: "main")
```

The package needs the engine mechanisms it builds on (`MeshOccluderComponent`,
`MeshFadeComponent`, `GaussianAssetLinkComponent`, the two-phase splat load), which are on the
fork's `develop` from the "generic occluder shell" refactor onwards.

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
        useRealWorldTint: false,     // XR: tint by the real-world lighting estimate
        alignment: GaussianSplatAlignment(  // where the splat sits in the mesh's space
            translation: SIMD3<Float>(0, 0.02, 0), yawDegrees: 90, scale: 1.02
        )
    )
)
```

From a scene: a `.untold` file whose entity carries a `gaussianAsset` record flagged
`meshTwin` arrives with a `GaussianAssetLinkComponent`; the system adopts it once, automatically
(`adoptsSceneLinks`), with the record's margin, exposure offset, swap distance and alignment.

`alignment` places the splat inside the mesh without a re-cook (offset in metres, yaw about
+Y in degrees, uniform scale; nil is identity): the system sets `alignment.matrix` on the
resident splat's `GaussianComponent.splatToEntity` (`setGaussianSplatToEntity`) every tick, so
changing `GaussianTwinComponent.options.alignment` moves the splat at once — what an editor's
align mode drives. It is stored in the scene record (`untoldengine gaussian-link --align-translate
x,y,z --align-yaw-degrees d --align-scale s`); the cook transform baked into the `.untoldgs`
header stays what it is.

`showsMeshWhileSwapped` is an authoring aid for that alignment: while it is set, the swapped
state keeps drawing the mesh's colour and installs no occluder shell, so the mesh and the
splat are both visible at once and the offset, yaw and scale can be judged against the surface
the splat should sit on. The splat still swaps in by distance and follows `alignment`; the
fades and the other states are unchanged, and clearing the flag restores the normal swapped
presentation on the next tick. An editor's align mode sets it (together with a zero swap
distance) on the twin's options only, never in the scene record; it is not meant for shipping
content.

A splat already on the entity when the twin is linked becomes its payload: it is hidden until
the swap, and its exposure offset and tint follow the twin's options from then on. The twin
owns the entity's `MeshOccluderComponent` and `MeshFadeComponent` while linked.

`removeEntityGaussianTwin(entityId:)` unlinks, drops the splat and shows the mesh; a scene link
on that entity is not adopted again. If the splat goes away under a running swap (the app
calls `removeEntityGaussian`, memory pressure), the mesh shows again at once and the swap
starts over from `armed`.

## What happens

| State | On screen |
|---|---|
| `armed` | The mesh. The payload may already be resident from an earlier swap. |
| `loading` | Still the mesh; nothing changes until the payload is on the GPU. |
| `crossFading` | The mesh dithers out (`MeshFadeComponent`) while the splat's opacity ramps in, over `crossFadeDuration`. The occluder shell is on. |
| `swapped` | The splat. The mesh draws no colour (`MeshOccluderComponent.drawsColor = false`) but keeps writing depth as a shrunk shell, casting shadows, colliding and being picked. With `showsMeshWhileSwapped` the mesh draws as usual instead (no shell). |
| `reverting` | The reverse fade when the camera leaves `swapDistanceMeters + hysteresisMeters`. Ends `armed`; the payload stays resident so the next swap is instant. |

Notes:

- Distance is measured from the camera to the entity's bounds centre.
- Each frame's fade step is capped at 100 ms, so the fade lasts `crossFadeDuration` at any
  refresh rate above 10 Hz.
- A batched mesh leaves its batch group when the swap starts and re-joins after reverting; the
  group is rebuilt over a few frames.
- Where splats cannot be drawn (the iOS simulator has no splat pipelines) twins stay armed.
- `GaussianTwinSystem.shared.uninstall()` stops the system and puts every twin back on its
  mesh; resident payloads are kept, hidden. `install()` picks the swaps up again.
- Soft objects differ from their mesh by centimetres: raise `occluderShrinkMeters` until the
  front of the capture stops clipping. `GaussianDebugOptions.shared.disableOccluderShell`
  turns the shells off for bisecting.

## Development

The package pins the engine fork's `develop` branch until the engine features ship in an
upstream release. To build against a local engine checkout:

```bash
swift package edit UntoldEngine --path ../../Untold/UntoldEngine
swift test
swift package unedit UntoldEngine
```
