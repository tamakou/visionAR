import Testing
import simd
@testable import visionAR

struct PoseEstimatorTests {

    @Test
    func poseFromValidTriangleProducesExpectedBasis() throws {
        let estimator = PoseEstimator()
        let p0 = simd_float3(0, 0, 0)
        let p1 = simd_float3(0, 0.12, 0)
        let p2 = simd_float3(0, 0, 0.12)

        let result = try estimator.poseFromThreePoints(p0, p1, p2)
        let expectedCenter = simd_float3(0, 0.04, 0.04)
        #expect(simd_distance(result.position, expectedCenter) < 1e-5)

        let rotation = simd_float3x3(result.orientation)
        let expectedX = simd_float3(0, 0, 1)
        let expectedY = simd_float3(0, -1, 0)
        let expectedZ = simd_float3(1, 0, 0)

        #expect(simd_distance(rotation.columns.0, expectedX) < 1e-5)
        #expect(simd_distance(rotation.columns.1, expectedY) < 1e-5)
        #expect(simd_distance(rotation.columns.2, expectedZ) < 1e-5)
    }

    @Test
    func degenerateTriangleThrows() {
        let estimator = PoseEstimator()
        let p0 = simd_float3(0, 0, 0)
        let p1 = simd_float3(0.1, 0, 0)
        let p2 = simd_float3(0.2, 0, 0)

        #expect(throws: PoseError.degenerateTriangle) {
            _ = try estimator.poseFromThreePoints(p0, p1, p2)
        }
    }
}
