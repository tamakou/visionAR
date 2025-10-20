import Foundation
import RealityKit

actor UsdLoader {
    private var cachedEntity: ModelEntity?
    private var cachedURL: URL?

    func loadModel(from url: URL) async throws -> ModelEntity {
        if let cachedEntity, cachedURL == url {
            return cachedEntity.clone(recursive: true)
        }
        let entity = try await ModelEntity.loadAsync(contentsOf: url).value
        entity.generateCollisionShapes(recursive: true)
        cachedEntity = entity
        cachedURL = url
        return entity.clone(recursive: true)
    }
}
