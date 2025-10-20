import Foundation
import RealityKit
import simd

@MainActor
final class PlacementController: ImageMarkerTrackerDelegate {
    enum State: Equatable {
        case idle
        case waitingForAnchors
        case poseApplied
    }

    private let poseEstimator = PoseEstimator()
    private let imageTracker: ImageMarkerTracker
    private let usdLoader: UsdLoader

    private(set) var rootEntity: Entity
    private let centerNode: Entity
    private var modelEntity: ModelEntity?

    private var awaitingPose = false

    private(set) var state: State = .idle {
        didSet { stateChangeHandler?(state) }
    }

    private(set) var statusMessage: String = "" {
        didSet { statusChangeHandler?(statusMessage) }
    }

    private(set) var lastPose: (position: simd_float3, orientation: simd_quatf)?

    var stateChangeHandler: ((State) -> Void)?
    var statusChangeHandler: ((String) -> Void)?
    var errorHandler: ((Error) -> Void)?

    init(imageTracker: ImageMarkerTracker, usdLoader: UsdLoader) {
        self.imageTracker = imageTracker
        self.usdLoader = usdLoader
        let root = Entity()
        root.name = "Root"
        let center = Entity()
        center.name = "CenterNode"
        root.addChild(center)
        rootEntity = root
        centerNode = center
        imageTracker.delegate = self
    }

    func prepareScene(content: RealityViewContent) {
        if rootEntity.parent == nil {
            content.add(rootEntity)
        }
    }

    func loadModel(from url: URL) async {
        do {
            let model = try await usdLoader.loadModel(from: url)
            centerNode.children.forEach { $0.removeFromParent() }
            model.isEnabled = false
            centerNode.addChild(model)
            modelEntity = model
            awaitingPose = true
            state = .waitingForAnchors
            statusMessage = "3枚のマーカーを検出すると配置します"
        } catch {
            errorHandler?(error)
            statusMessage = "モデル読み込みに失敗しました"
        }
    }

    func requestReposition() {
        guard modelEntity != nil else { return }
        awaitingPose = true
        modelEntity?.isEnabled = false
        state = .waitingForAnchors
        statusMessage = "再配置のために3枚のマーカーを揃えてください"
    }

    func imageMarkerTracker(_ tracker: ImageMarkerTracker, didUpdate anchors: [String : simd_float3]) {
        guard awaitingPose else { return }
        guard let p0 = anchors["MarkerA"], let p1 = anchors["MarkerB"], let p2 = anchors["MarkerC"] else {
            return
        }
        do {
            let pose = try poseEstimator.poseFromThreePoints(p0, p1, p2)
            applyPose(pose)
        } catch {
            awaitingPose = true
            modelEntity?.isEnabled = false
            errorHandler?(error)
            statusMessage = "マーカー配置が安定するまで待機しています"
        }
    }

    func imageMarkerTracker(_ tracker: ImageMarkerTracker, didFail error: Error) {
        errorHandler?(error)
    }

    private func applyPose(_ pose: (position: simd_float3, orientation: simd_quatf)) {
        centerNode.transform = Transform(scale: SIMD3<Float>(repeating: 1),
                                         rotation: pose.orientation,
                                         translation: pose.position)
        modelEntity?.isEnabled = true
        awaitingPose = false
        lastPose = pose
        state = .poseApplied
        statusMessage = "モデルを配置しました"
    }
}
