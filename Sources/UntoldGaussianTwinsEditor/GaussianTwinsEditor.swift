//
//  GaussianTwinsEditor.swift
//  UntoldGaussianTwins
//
//  The package's editor side: what the Untold editor adds to its menus while a project that
//  lists this package is open. Only the editor compiles this folder (untold-package.json names
//  it as editorSources); no game target does. The editor links the runtime, so these items
//  drive the same GaussianTwinSystem its Inspector's Splat Twin section works with.
//

import UntoldComponentKit
import UntoldEngine
import UntoldGaussianTwins

/// View > Preview Splat Twins, and Debug > Splat Debug.
final class GaussianTwinsEditor: EditorMenuPlugin {
    /// Whether `GaussianTwinSystem` runs in the editor viewport, swapping linked meshes for
    /// their splat twins as the scene camera approaches, exactly as an app running the system
    /// would. Persisted per project, on by default.
    @UntoldMenu(.view, "Preview Splat Twins",
                tooltip: "Swap meshes linked to a .untoldgs twin for the splat as the scene camera approaches, as GaussianTwinSystem does in an app.")
    var previewTwins = true

    /// The engine's Gaussian splat debug switches: each turns off one stage of the splat
    /// pipeline so a rendering artefact can be bisected live. Not persisted, so a switch left
    /// on by mistake does not follow the project into the next session.
    @UntoldMenu(.debug, "Splat Debug/Disable Splat HZB Occlusion Cull",
                tooltip: "Splats are no longer culled against the previous frame's depth pyramid.", persist: false)
    var disableHZBOcclusionCull = false

    @UntoldMenu(.debug, "Splat Debug/Disable Splat Opaque Depth Test",
                tooltip: "Splat fragments are no longer hidden behind meshes, gizmos or the grid.", persist: false)
    var disableOpaqueDepthTest = false

    @UntoldMenu(.debug, "Splat Debug/Disable Splat Per-Pixel Blend Cap",
                tooltip: "Every sorted splat that reaches a pixel is blended, not just the first 64.", persist: false)
    var disableBlendCap = false

    @UntoldMenu(.debug, "Splat Debug/Reset Link Adoption",
                tooltip: "Forget which scene links the system already adopted, so every link is examined again.")
    var resetLinkAdoption = UntoldMenuAction { GaussianTwinSystem.shared.resetSceneLinkAdoption() }

    override func onLoad() {
        apply()
    }

    override func menuDidChange(_: UntoldMenuDomain, _: String) {
        apply()
    }

    /// The old scene's entities are gone and their ids will be reused, so adoption starts over.
    override func onSceneReset() {
        GaussianTwinSystem.shared.resetSceneLinkAdoption()
    }

    override func onUnload() {
        GaussianTwinSystem.shared.uninstall()
    }

    private func apply() {
        let system = GaussianTwinSystem.shared
        if previewTwins {
            // Links the system examined while it was off (or before a reload) are adopted
            // again; `uninstall()` keeps its examined set.
            if system.isInstalled == false {
                system.resetSceneLinkAdoption()
                system.install()
            }
        } else {
            system.uninstall()
        }
        let debug = GaussianDebugOptions.shared
        debug.disableHZBOcclusionCull = disableHZBOcclusionCull
        debug.disableOpaqueDepthTest = disableOpaqueDepthTest
        debug.disableBlendCap = disableBlendCap
    }
}
