import Foundation
import ARKit
import CoreGraphics
import ImageIO
import simd

@MainActor
protocol ImageMarkerTrackerDelegate: AnyObject {
    func imageMarkerTracker(_ tracker: ImageMarkerTracker, didUpdate anchors: [String: simd_float3])
    func imageMarkerTracker(_ tracker: ImageMarkerTracker, didFail error: Error)
}

@MainActor
final class ImageMarkerTracker {
    enum TrackerError: LocalizedError {
        case referenceImageMissing(String)
        case providerNotSupported

        var errorDescription: String? {
            switch self {
            case .referenceImageMissing(let name):
                return "参照イメージ \(name) を読み込めませんでした"
            case .providerNotSupported:
                return "このデバイスでは画像トラッキングがサポートされていません"
            }
        }
    }

    private let session = ARKitSession()
    private var trackingProvider: ImageTrackingProvider?
    private var updatesTask: Task<Void, Never>?

    weak var delegate: ImageMarkerTrackerDelegate?

    private(set) var anchors: [String: simd_float3] = [:]

    private let referenceMarkers: [MarkerDefinition]

    struct MarkerDefinition {
        let name: String
        let resourceName: String
        let physicalWidth: Float
    }

    init(markers: [MarkerDefinition]) {
        referenceMarkers = markers
    }

    func startTracking() async {
        do {
            let provider = try makeProvider()
            trackingProvider = provider
            try await session.run([provider])
            listenForUpdates(provider: provider)
        } catch {
            delegate?.imageMarkerTracker(self, didFail: error)
        }
    }

    func stopTracking() {
        updatesTask?.cancel()
        updatesTask = nil
        anchors.removeAll()
        trackingProvider = nil
        Task {
            try? await session.stop()
        }
    }

    private func makeProvider() throws -> ImageTrackingProvider {
        var referenceImages: [ARReferenceImage] = []
        for marker in referenceMarkers {
            let cgImage = try loadCGImage(for: marker)
            let referenceImage = ARReferenceImage(cgImage: cgImage,
                                                  orientation: .up,
                                                  physicalWidth: CGFloat(marker.physicalWidth))
            referenceImage.name = marker.name
            referenceImages.append(referenceImage)
        }
        guard ImageTrackingProvider.isSupported else {
            throw TrackerError.providerNotSupported
        }
        return try ImageTrackingProvider(referenceImages: referenceImages)
    }

    private func listenForUpdates(provider: ImageTrackingProvider) {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in provider.anchorUpdates {
                await MainActor.run {
                    self?.handle(update: update)
                }
            }
        }
    }

    private func handle(update: ARKit.AnchorUpdate<ARImageAnchor>) {
        switch update.event {
        case .added(let anchor), .updated(let anchor):
            guard let name = anchor.referenceImage.name else { return }
            let position = simd_float3(anchor.transform.columns.3.x,
                                       anchor.transform.columns.3.y,
                                       anchor.transform.columns.3.z)
            anchors[name] = position
        case .removed(let anchor):
            if let name = anchor.referenceImage.name {
                anchors.removeValue(forKey: name)
            }
        @unknown default:
            break
        }
        delegate?.imageMarkerTracker(self, didUpdate: anchors)
    }

    private func loadCGImage(for marker: MarkerDefinition) throws -> CGImage {
        if let url = Bundle.main.url(forResource: marker.resourceName, withExtension: nil) ??
            Bundle.main.url(forResource: marker.resourceName, withExtension: "png") ??
            Bundle.main.url(forResource: marker.resourceName, withExtension: "jpg"),
           let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
            return cgImage
        }
        return try placeholderImage(for: marker)
    }

    private func placeholderImage(for marker: MarkerDefinition) throws -> CGImage {
        let size = CGSize(width: 512, height: 512)
        guard let context = CGContext(data: nil,
                                      width: Int(size.width),
                                      height: Int(size.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw TrackerError.referenceImageMissing(marker.resourceName)
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(20)
        context.stroke(CGRect(x: 10, y: 10, width: size.width - 20, height: size.height - 20))

        context.setFillColor(color(for: marker.name))
        let insetRect = CGRect(x: size.width * 0.2,
                               y: size.height * 0.2,
                               width: size.width * 0.6,
                               height: size.height * 0.6)
        context.fill(insetRect)
        guard let cgImage = context.makeImage() else {
            throw TrackerError.referenceImageMissing(marker.resourceName)
        }
        return cgImage
    }

    private func color(for name: String) -> CGColor {
        switch name {
        case "MarkerA":
            return CGColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1)
        case "MarkerB":
            return CGColor(red: 0.1, green: 0.6, blue: 0.2, alpha: 1)
        default:
            return CGColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1)
        }
    }
}
