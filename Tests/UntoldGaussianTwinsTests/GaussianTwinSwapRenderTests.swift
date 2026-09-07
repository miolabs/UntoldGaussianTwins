//
//  GaussianTwinSwapRenderTests.swift
//  UntoldGaussianTwins
//
//  The whole swap against the engine with a real mesh and a real splat: load on approach,
//  fade, swap, revert by distance, recovery when the splat goes away, and unlinking. Needs a
//  Metal device; skipped where there is none.
//

#if os(macOS)
    import AppKit
    import Metal
    import simd
    import UntoldEngine
    @testable import UntoldGaussianTwins
    import XCTest

    @MainActor
    final class GaussianTwinSwapRenderTests: XCTestCase {
        private var renderer: UntoldRenderer?

        override func setUp() async throws {
            try await super.setUp()
            guard let renderer = UntoldRenderer.create() else {
                throw XCTSkip("No Metal renderer available")
            }
            self.renderer = renderer
            let size = CGSize(width: 320, height: 240)
            renderer.metalView.autoResizeDrawable = false
            renderer.metalView.drawableSize = size
            renderer.metalView.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
            renderer.mtkView(renderer.metalView, drawableSizeWillChange: size)
            renderer.metalView.delegate = nil
            GaussianTwinSystem.shared.splatRenderingAvailableOverride = true
            GaussianTwinSystem.shared.install()
        }

        override func tearDown() async throws {
            GaussianTwinSystem.shared.uninstall()
            GaussianTwinSystem.shared.splatRenderingAvailableOverride = nil
            GaussianTwinSystem.shared.resetSceneLinkAdoption()
            CameraSystem.shared.activeCamera = nil
            destroyAllEntities()
            renderer = nil
            try await super.tearDown()
        }

        private func testPLYURL() throws -> URL {
            try XCTUnwrap(Bundle.module.url(forResource: "test_gaussians", withExtension: "ply", subdirectory: "Resources"))
        }

        private func makeCamera(at eye: simd_float3) -> EntityID {
            let camera = createEntity()
            registerComponent(entityId: camera, componentType: CameraComponent.self)
            CameraSystem.shared.activeCamera = camera
            cameraLookAt(entityId: camera, eye: eye, target: .zero, up: simd_float3(0, 1, 0))
            return camera
        }

        private func makeCubeEntity() -> EntityID {
            let entity = createEntity()
            setEntityMeshDirect(entityId: entity, meshes: BasicPrimitives.createCube(extent: 1.0), assetName: "cube")
            return entity
        }

        private func tick(_ times: Int = 1, deltaTime: Float = 0.016) {
            for _ in 0 ..< times {
                GaussianTwinSystem.shared.update(deltaTime: deltaTime)
            }
        }

        private func waitForPayload(on entity: EntityID) async throws {
            let deadline = Date().addingTimeInterval(15)
            while scene.get(component: GaussianComponent.self, for: entity) == nil,
                  scene.get(component: GaussianTwinComponent.self, for: entity)?.loadFailed == false,
                  Date() < deadline
            {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertNotNil(scene.get(component: GaussianComponent.self, for: entity), "The payload should load")
        }

        func testSwapLoadsFadesSwapsAndRevertsByDistance() async throws {
            let camera = makeCamera(at: simd_float3(0, 0, 40))
            let entity = makeCubeEntity()
            try setEntityGaussianTwin(
                entityId: entity,
                payloadURL: testPLYURL(),
                options: GaussianTwinOptions(swapDistanceMeters: 12, hysteresisMeters: 1, crossFadeDuration: 0.25, exposureOffsetEV: 0.5)
            )
            let twin = try XCTUnwrap(scene.get(component: GaussianTwinComponent.self, for: entity))

            tick()
            XCTAssertEqual(twin.state, .armed, "Far away nothing happens")
            XCTAssertNil(scene.get(component: GaussianComponent.self, for: entity))

            cameraLookAt(entityId: camera, eye: simd_float3(0, 0, 5), target: .zero, up: simd_float3(0, 1, 0))
            tick()
            XCTAssertEqual(twin.state, .loading)
            try await waitForPayload(on: entity)
            let gaussian = try XCTUnwrap(scene.get(component: GaussianComponent.self, for: entity))
            XCTAssertEqual(gaussian.opacityScale, 0, "Resident but hidden until the fade")

            tick()
            XCTAssertEqual(twin.state, .crossFading)
            XCTAssertEqual(gaussian.exposureOffsetEV, 0.5, "The twin's exposure offset reaches the splat")
            let occluder = try XCTUnwrap(scene.get(component: MeshOccluderComponent.self, for: entity), "The shell is on from the first fade frame")
            XCTAssertTrue(occluder.drawsColor)
            let fade = try XCTUnwrap(scene.get(component: MeshFadeComponent.self, for: entity))
            XCTAssertEqual(fade.direction, .fadeOut)

            tick(2, deltaTime: 0.1)
            XCTAssertEqual(twin.state, .crossFading)
            XCTAssertEqual(fade.progress, 0.8, accuracy: 1e-4)
            XCTAssertEqual(gaussian.opacityScale, 0.8, accuracy: 1e-4, "Mesh dither and splat opacity move together")

            tick(1, deltaTime: 0.1)
            XCTAssertEqual(twin.state, .swapped)
            XCTAssertFalse(occluder.drawsColor, "Swapped: colour off, shell on")
            XCTAssertNil(scene.get(component: MeshFadeComponent.self, for: entity))
            XCTAssertEqual(gaussian.opacityScale, 1)

            cameraLookAt(entityId: camera, eye: simd_float3(0, 0, 40), target: .zero, up: simd_float3(0, 1, 0))
            tick()
            XCTAssertEqual(twin.state, .reverting)
            XCTAssertTrue(occluder.drawsColor, "Reverting: colour back, dithering in")
            XCTAssertEqual(scene.get(component: MeshFadeComponent.self, for: entity)?.direction, .fadeIn)

            tick(3, deltaTime: 0.1)
            XCTAssertEqual(twin.state, .armed)
            XCTAssertNil(scene.get(component: MeshOccluderComponent.self, for: entity), "Armed: plain mesh")
            XCTAssertNil(scene.get(component: MeshFadeComponent.self, for: entity))
            XCTAssertEqual(gaussian.opacityScale, 0)
            XCTAssertNotNil(scene.get(component: GaussianComponent.self, for: entity), "The payload stays resident")

            cameraLookAt(entityId: camera, eye: simd_float3(0, 0, 5), target: .zero, up: simd_float3(0, 1, 0))
            tick()
            XCTAssertEqual(twin.state, .crossFading, "Resident again: the swap is instant")
        }

        func testLosingTheSplatWhileSwappedShowsTheMeshAgain() async throws {
            makeCamera(at: simd_float3(0, 0, 5))
            let entity = makeCubeEntity()
            try setEntityGaussianTwin(entityId: entity, payloadURL: testPLYURL(), options: GaussianTwinOptions(swapDistanceMeters: 0, crossFadeDuration: 0.1))
            let twin = try XCTUnwrap(scene.get(component: GaussianTwinComponent.self, for: entity))
            tick()
            try await waitForPayload(on: entity)
            tick(3, deltaTime: 0.1)
            XCTAssertEqual(twin.state, .swapped)
            XCTAssertEqual(scene.get(component: MeshOccluderComponent.self, for: entity)?.drawsColor, false)

            // The app drops the splat through the engine API while the swap is on.
            removeEntityGaussian(entityId: entity)
            tick()
            XCTAssertEqual(twin.state, .armed, "Back to the mesh at once")
            XCTAssertNil(scene.get(component: MeshOccluderComponent.self, for: entity), "No colour-off shell without a splat to show")
            XCTAssertNil(scene.get(component: MeshFadeComponent.self, for: entity))
            tick()
            XCTAssertEqual(twin.state, .loading, "And loading again, since the camera is still near")
            twin.loadTask?.cancel()
        }

        func testUnlinkingDropsTheSplatAndItsPresentation() async throws {
            makeCamera(at: simd_float3(0, 0, 5))
            let entity = makeCubeEntity()
            try setEntityGaussianTwin(entityId: entity, payloadURL: testPLYURL(), options: GaussianTwinOptions(swapDistanceMeters: 0, crossFadeDuration: 0.1))
            tick()
            try await waitForPayload(on: entity)
            tick(3, deltaTime: 0.1)
            XCTAssertEqual(scene.get(component: GaussianTwinComponent.self, for: entity)?.state, .swapped)

            removeEntityGaussianTwin(entityId: entity)
            XCTAssertNil(scene.get(component: GaussianTwinComponent.self, for: entity))
            XCTAssertNil(scene.get(component: GaussianComponent.self, for: entity), "The splat went with the twin")
            XCTAssertNil(scene.get(component: MeshOccluderComponent.self, for: entity))
            XCTAssertNil(scene.get(component: MeshFadeComponent.self, for: entity))
            XCTAssertEqual(MemoryBudgetManager.shared.auxiliaryMeshBytes(for: entity), 0, "Only the mesh's bytes remain")
            tick()
            XCTAssertNil(scene.get(component: GaussianTwinComponent.self, for: entity), "Nothing re-links it")
        }
    }
#endif
