//
//  GaussianTwinStateMachineTests.swift
//  UntoldGaussianTwins
//

import Foundation
import UntoldEngine
@testable import UntoldGaussianTwins
import XCTest

/// The swap's state machine and distance rule, and the component's registration.
@MainActor
final class GaussianTwinStateMachineTests: XCTestCase {
    private func step(
        _ state: GaussianTwinState,
        progress: Float = 0,
        wantsSwap: Bool = true,
        resident: Bool = true,
        loadFailed: Bool = false,
        deltaTime: Float = 0.05,
        duration: Float = 0.25
    ) -> GaussianTwinStep {
        gaussianTwinStep(
            state: state,
            progress: progress,
            wantsSwap: wantsSwap,
            payloadResident: resident,
            loadFailed: loadFailed,
            deltaTime: deltaTime,
            duration: duration
        )
    }

    // MARK: - State machine

    func testArmedWaitsUntilTheSwapIsWanted() {
        XCTAssertEqual(step(.armed, wantsSwap: false), GaussianTwinStep(state: .armed, progress: 0))
        XCTAssertEqual(step(.armed, resident: false), GaussianTwinStep(state: .loading, progress: 0), "Not resident: load first")
        XCTAssertEqual(step(.armed, resident: true), GaussianTwinStep(state: .crossFading, progress: 0), "Resident: fade at once")
        XCTAssertEqual(step(.armed, resident: false, loadFailed: true), GaussianTwinStep(state: .armed, progress: 0), "A failed load does not retry")
    }

    func testLoadingChangesNothingUntilThePayloadIsResident() {
        XCTAssertEqual(step(.loading, resident: false), GaussianTwinStep(state: .loading, progress: 0))
        XCTAssertEqual(step(.loading, resident: true), GaussianTwinStep(state: .crossFading, progress: 0))
        XCTAssertEqual(step(.loading, wantsSwap: false, resident: true), GaussianTwinStep(state: .armed, progress: 0), "Camera left meanwhile: stay on the mesh, keep the payload")
        XCTAssertEqual(step(.loading, resident: false, loadFailed: true), GaussianTwinStep(state: .armed, progress: 0))
    }

    func testCrossFadeRunsOverTheDurationAndEndsSwapped() {
        var current = step(.crossFading, progress: 0, deltaTime: 0.1, duration: 0.25)
        XCTAssertEqual(current.state, .crossFading)
        XCTAssertEqual(current.progress, 0.4, accuracy: 1e-5)
        current = step(.crossFading, progress: current.progress, deltaTime: 0.1, duration: 0.25)
        XCTAssertEqual(current.progress, 0.8, accuracy: 1e-5)
        current = step(.crossFading, progress: current.progress, deltaTime: 0.1, duration: 0.25)
        XCTAssertEqual(current, GaussianTwinStep(state: .swapped, progress: 1))
        XCTAssertEqual(step(.swapped), GaussianTwinStep(state: .swapped, progress: 1))
    }

    func testRevertMirrorsTheFadeAndCanTurnAroundMidway() {
        XCTAssertEqual(step(.swapped, wantsSwap: false), GaussianTwinStep(state: .reverting, progress: 0))
        // Turning around keeps the on-screen blend where it is: 30% faded in becomes 70% reverted.
        XCTAssertEqual(step(.crossFading, progress: 0.3, wantsSwap: false), GaussianTwinStep(state: .reverting, progress: 0.7))
        XCTAssertEqual(step(.reverting, progress: 0.7, wantsSwap: true), GaussianTwinStep(state: .crossFading, progress: 0.3))
        var current = step(.reverting, progress: 0.9, wantsSwap: false, deltaTime: 0.1, duration: 0.25)
        XCTAssertEqual(current, GaussianTwinStep(state: .armed, progress: 0), "The reverse fade ends armed")
        current = step(.reverting, progress: 0, wantsSwap: false, deltaTime: 0.05, duration: 0.25)
        XCTAssertEqual(current.state, .reverting)
        XCTAssertEqual(current.progress, 0.2, accuracy: 1e-5)
    }

    func testAZeroDurationDoesNotDivideByZero() {
        XCTAssertEqual(step(.crossFading, deltaTime: 0.016, duration: 0), GaussianTwinStep(state: .swapped, progress: 1))
    }

    // MARK: - Distance rule and opacity mapping

    func testSwapDistanceWithHysteresis() {
        let options = GaussianTwinOptions(swapDistanceMeters: 10, hysteresisMeters: 2)
        XCTAssertTrue(gaussianTwinWantsSwap(distance: 9, options: options, state: .armed))
        XCTAssertFalse(gaussianTwinWantsSwap(distance: 11, options: options, state: .armed), "Arming needs the inner threshold")
        XCTAssertTrue(gaussianTwinWantsSwap(distance: 11, options: options, state: .swapped), "Swapped holds through the band")
        XCTAssertTrue(gaussianTwinWantsSwap(distance: 11, options: options, state: .loading))
        XCTAssertFalse(gaussianTwinWantsSwap(distance: 12.5, options: options, state: .swapped), "Beyond the band it reverts")
        XCTAssertFalse(gaussianTwinWantsSwap(distance: 11, options: options, state: .reverting), "Re-swapping mid-revert needs the inner threshold again")

        let always = GaussianTwinOptions(swapDistanceMeters: 0)
        XCTAssertTrue(gaussianTwinWantsSwap(distance: 1000, options: always, state: .armed))
    }

    func testSplatOpacityFollowsTheState() {
        XCTAssertEqual(gaussianTwinSplatOpacity(state: .armed, progress: 0.5), 0)
        XCTAssertEqual(gaussianTwinSplatOpacity(state: .loading, progress: 0.5), 0)
        XCTAssertEqual(gaussianTwinSplatOpacity(state: .crossFading, progress: 0.25), 0.25)
        XCTAssertEqual(gaussianTwinSplatOpacity(state: .swapped, progress: 0), 1)
        XCTAssertEqual(gaussianTwinSplatOpacity(state: .reverting, progress: 0.25), 0.75)
    }

    func testOptionsFromASceneLinkTakeTheRecordValues() {
        let link = GaussianAssetLinkComponent()
        link.swapDistanceMeters = 4
        link.occluderShrinkMeters = 0.03
        link.exposureOffsetEV = 0.5
        let options = GaussianTwinOptions(link: link)
        XCTAssertEqual(options.swapDistanceMeters, 4)
        XCTAssertEqual(options.occluderShrinkMeters, 0.03)
        XCTAssertEqual(options.exposureOffsetEV, 0.5)
        XCTAssertEqual(options.crossFadeDuration, 0.25, "Not in the record: the default")
    }

    // MARK: - Registration (needs the engine's scene, no renderer)

    func testSetEntityGaussianTwinRegistersAnArmedComponentAndRemoveUnlinks() {
        let entity = createEntity()
        registerTransformComponent(entityId: entity)
        let url = URL(fileURLWithPath: "/tmp/chair.untoldgs")
        let options = GaussianTwinOptions(swapDistanceMeters: 3, crossFadeDuration: 0.3, occluderShrinkMeters: 0.05, exposureOffsetEV: 0.5, useRealWorldTint: true)

        setEntityGaussianTwin(entityId: entity, payloadURL: url, options: options)

        let twin = scene.get(component: GaussianTwinComponent.self, for: entity)
        XCTAssertEqual(twin?.payloadURL, url)
        XCTAssertEqual(twin?.options, options)
        XCTAssertEqual(twin?.state, .armed)
        XCTAssertNil(scene.get(component: GaussianComponent.self, for: entity), "Linking loads nothing")
        XCTAssertNil(scene.get(component: MeshOccluderComponent.self, for: entity), "Armed: no shell")

        removeEntityGaussianTwin(entityId: entity)
        XCTAssertNil(scene.get(component: GaussianTwinComponent.self, for: entity))
        destroyEntity(entityId: entity)
    }

    func testTwinWithoutMeshStaysArmedAndLoadsNothing() {
        GaussianTwinSystem.shared.splatRenderingAvailableOverride = true
        defer { GaussianTwinSystem.shared.splatRenderingAvailableOverride = nil }
        let entity = createEntity()
        registerTransformComponent(entityId: entity)
        setEntityGaussianTwin(entityId: entity, payloadURL: URL(fileURLWithPath: "/tmp/chair.untoldgs"))

        let camera = createEntity()
        registerComponent(entityId: camera, componentType: CameraComponent.self)
        CameraSystem.shared.activeCamera = camera

        GaussianTwinSystem.shared.update(deltaTime: 0.016)

        let twin = scene.get(component: GaussianTwinComponent.self, for: entity)
        XCTAssertEqual(twin?.state, .armed, "Nothing to swap from yet")
        XCTAssertNil(twin?.loadTask)
        removeEntityGaussianTwin(entityId: entity)
        destroyEntity(entityId: entity)
        destroyEntity(entityId: camera)
    }
}
