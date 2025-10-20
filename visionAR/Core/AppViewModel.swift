import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppViewModel {
    enum FolderState: Equatable {
        case disconnected
        case connected(URL)
    }

    @ObservationIgnored private let folderAccessManager = FolderAccessManager()
    @ObservationIgnored private var modelIndexer: ModelIndexer?
    @ObservationIgnored private let usdLoader = UsdLoader()
    @ObservationIgnored private let imageTracker: ImageMarkerTracker
    @ObservationIgnored let placementController: PlacementController

    var folderState: FolderState = .disconnected
    var isImporting = false
    var models: [ModelMetadata] = []
    var selectedModelID: String?
    var statusText: String = "フォルダを接続してください"
    var latestErrorMessage: String?
    var isShowingErrorAlert = false
    private var hasStartedTracking = false

    let nonMedicalNotice = "本アプリの表示は参考情報であり、医療機器ではありません。"

    init() {
        imageTracker = ImageMarkerTracker(markers: [
            .init(name: "MarkerA", resourceName: "MarkerA", physicalWidth: 0.12),
            .init(name: "MarkerB", resourceName: "MarkerB", physicalWidth: 0.12),
            .init(name: "MarkerC", resourceName: "MarkerC", physicalWidth: 0.12)
        ])
        placementController = PlacementController(imageTracker: imageTracker, usdLoader: usdLoader)
        placementController.statusChangeHandler = { [weak self] newStatus in
            self?.statusText = newStatus
        }
        placementController.errorHandler = { [weak self] error in
            self?.latestErrorMessage = error.localizedDescription
            self?.isShowingErrorAlert = true
        }

        Task { await bootstrap() }
    }

    func bootstrap() async {
        do {
            if modelIndexer == nil {
                modelIndexer = try await ModelIndexer(folderAccessManager: folderAccessManager)
            }
            if let restoredURL = try await folderAccessManager.startAccessingIfNeeded() {
                folderState = .connected(restoredURL)
                await startTrackingIfNeeded()
                try await performImport(from: restoredURL)
            } else {
                await startTrackingIfNeeded()
            }
        } catch {
            latestErrorMessage = error.localizedDescription
            isShowingErrorAlert = true
        }
    }

    func startTrackingIfNeeded() async {
        guard !hasStartedTracking else { return }
        hasStartedTracking = true
        await imageTracker.startTracking()
    }

    func handleFolderSelection(url: URL) {
        Task {
            var shouldStopAccessing = false
            if url.startAccessingSecurityScopedResource() {
                shouldStopAccessing = true
            }
            defer {
                if shouldStopAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                try await folderAccessManager.persistSecurityScopedBookmark(for: url)
                folderState = .connected(url)
                if modelIndexer == nil {
                    modelIndexer = try await ModelIndexer(folderAccessManager: folderAccessManager)
                }
                await startTrackingIfNeeded()
                try await performImport(from: url)
            } catch {
                latestErrorMessage = error.localizedDescription
                isShowingErrorAlert = true
            }
        }
    }

    func performImport() {
        guard case let .connected(url) = folderState else {
            statusText = "フォルダを接続してください"
            return
        }
        Task {
            do {
                try await performImport(from: url)
            } catch {
                latestErrorMessage = error.localizedDescription
                isShowingErrorAlert = true
            }
        }
    }

    private func performImport(from url: URL) async throws {
        guard let indexer else { return }
        isImporting = true
        defer { isImporting = false }
        let refreshed = try await indexer.refreshModels(from: url)
        models = refreshed
        if refreshed.isEmpty {
            statusText = "USDZモデルが見つかりませんでした"
        } else {
            statusText = "モデルを選択してください"
        }
    }

    func selectModel(_ model: ModelMetadata) {
        selectedModelID = model.id
        Task {
            guard let indexer else { return }
            do {
                let localURL = try await indexer.localURL(for: model)
                await placementController.loadModel(from: localURL)
            } catch {
                latestErrorMessage = error.localizedDescription
                isShowingErrorAlert = true
            }
        }
    }

    func requestReposition() {
        placementController.requestReposition()
    }
}
