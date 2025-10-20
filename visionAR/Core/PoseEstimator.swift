import Foundation
import simd

enum PoseError: Error {
    case degenerateTriangle
    case invalidVector
}

struct PoseEstimator {
    func poseFromThreePoints(_ p0: simd_float3,
                             _ p1: simd_float3,
                             _ p2: simd_float3) throws -> (position: simd_float3, orientation: simd_quatf) {
        let center = (p0 + p1 + p2) / 3

        let v01 = p1 - p0
        let v02 = p2 - p0
        let crossZ = simd_cross(v01, v02)
        let crossLen = simd_length(crossZ)
        guard crossLen > 1e-5 else { throw PoseError.degenerateTriangle }

        var z = simd_normalize(crossZ)
        var y = simd_normalize(p0 - p1)
        var x = simd_normalize(simd_cross(y, z))

        guard x.allFinite && y.allFinite && z.allFinite else { throw PoseError.invalidVector }

        let rotationMatrix = simd_float3x3(columns: (x, y, z))
        let quaternion = simd_quaternion(rotationMatrix)
        return (center, quaternion)
    }
}
