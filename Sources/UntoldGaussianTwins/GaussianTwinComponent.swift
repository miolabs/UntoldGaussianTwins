//
//  GaussianTwinComponent.swift
//  UntoldGaussianTwins
//
//  A mesh entity linked to the captured Gaussian-splat twin that stands in for it up close.
//

import Foundation
import UntoldEngine

/// Where a mesh entity with a captured splat twin stands in the swap.
public enum GaussianTwinState: Int, Sendable, Equatable {
    /// The mesh is drawn as usual; the splat is not shown (it may or may not be resident).
    case armed
    /// The splat payload is being read; nothing changes on screen until it is resident.
    case loading
    /// The mesh colour dithers out while the splat's opacity ramps in, over `crossFadeDuration`.
    case crossFading
    /// The splat is shown. The mesh keeps writing depth (as a shrunk shell), shadows and physics.
    case swapped
    /// The reverse fade: the mesh dithers back in while the splat ramps out.
    case reverting
}

/// Per-entity settings of the mesh-to-splat swap. Seeded from a scene's `gaussianAsset` record
/// (`GaussianAssetLinkComponent`) when the twin comes from a `.untold` file.
public struct GaussianTwinOptions: Sendable, Equatable {
    /// Camera distance to the mesh's bounds centre below which the swap arms and runs;
    /// 0 swaps at any distance.
    public var swapDistanceMeters: Float
    /// Added to `swapDistanceMeters` before the swap reverts, so a camera hovering at the
    /// threshold does not flip the object back and forth.
    public var hysteresisMeters: Float
    /// Length of the cross-fade in seconds (wall-clock), both ways.
    public var crossFadeDuration: Float
    /// Metres the depth-only occluder shell is shrunk along the mesh normals while the splat
    /// is shown, so splats on and just outside the surface are not hidden by their own mesh.
    public var occluderShrinkMeters: Float
    /// Exposure offset in EV applied to the splat on top of its capture exposure.
    public var exposureOffsetEV: Float
    /// In XR, tint the splat by the real-world lighting estimate (`GaussianComponent.useRealWorldTint`).
    public var useRealWorldTint: Bool

    public init(
        swapDistanceMeters: Float = 0,
        hysteresisMeters: Float = 0.5,
        crossFadeDuration: Float = 0.25,
        occluderShrinkMeters: Float = 0.02,
        exposureOffsetEV: Float = 0,
        useRealWorldTint: Bool = false
    ) {
        self.swapDistanceMeters = swapDistanceMeters
        self.hysteresisMeters = hysteresisMeters
        self.crossFadeDuration = crossFadeDuration
        self.occluderShrinkMeters = occluderShrinkMeters
        self.exposureOffsetEV = exposureOffsetEV
        self.useRealWorldTint = useRealWorldTint
    }

    /// The options a scene's `gaussianAsset` record asks for.
    public init(link: GaussianAssetLinkComponent) {
        self.init(
            swapDistanceMeters: link.swapDistanceMeters,
            occluderShrinkMeters: link.occluderShrinkMeters,
            exposureOffsetEV: link.exposureOffsetEV
        )
    }
}

/// Links a mesh entity to the captured splat that stands in for it up close. `GaussianTwinSystem`
/// loads the payload onto the same entity, cross-fades the two through the engine's
/// `MeshFadeComponent` and `GaussianComponent.opacityScale`, and keeps the mesh's depth through a
/// `MeshOccluderComponent` while the splat is shown. Attached by `setEntityGaussianTwin`, or
/// adopted from a `.untold` scene's `GaussianAssetLinkComponent` flagged `meshTwin`.
public final class GaussianTwinComponent: Component {
    /// The `.untoldgs` (or `.ply`) file loaded when the swap arms.
    public var payloadURL: URL?
    public var options = GaussianTwinOptions()
    public internal(set) var state: GaussianTwinState = .armed
    /// 0...1 progress of the running cross-fade (`.crossFading` and `.reverting` only).
    public internal(set) var fadeProgress: Float = 0
    /// Set once a payload load has failed; the swap then stays armed and does not retry.
    public internal(set) var loadFailed = false

    /// Bumped on every link, relink and unlink; a load applies only if it still matches.
    var loadGeneration: UInt32 = 0
    var loadTask: Task<Void, Never>?

    public required init() {}
}
