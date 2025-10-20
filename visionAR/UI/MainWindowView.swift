import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @State private var showingFileImporter = false
    @State private var hasOpenedImmersiveSpace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            controlSection
            modelListSection
            Spacer()
            footerNotice
        }
        .padding(24)
        .background(Color.clear)
        .task { await ensureImmersiveSpaceOpened() }
        .fileImporter(isPresented: $showingFileImporter,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let folder = urls.first {
                    viewModel.handleFolderSelection(url: folder)
                }
            case .failure(let error):
                viewModel.latestErrorMessage = error.localizedDescription
                viewModel.isShowingErrorAlert = true
            }
        }
        .alert("エラー", isPresented: $viewModel.isShowingErrorAlert, presenting: viewModel.latestErrorMessage) { _ in
            Button("閉じる", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Vision AR Overlay")
                .font(.title2)
                .fontWeight(.semibold)
            Text(viewModel.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var controlSection: some View {
        HStack(spacing: 12) {
            Button("フォルダを接続") {
                showingFileImporter = true
            }
            .buttonStyle(.borderedProminent)

            Button("インポート") {
                viewModel.performImport()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isImporting)

            Button("再配置") {
                viewModel.requestReposition()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.selectedModelID == nil)
        }
    }

    private var modelListSection: some View {
        Group {
            if viewModel.isImporting {
                ProgressView("スキャン中…")
            } else {
                List(viewModel.models) { model in
                    Button {
                        viewModel.selectModel(model)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.fileName)
                                    .font(.headline)
                                Text(model.relativePath)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.selectedModelID == model.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxHeight: 260)
            }
        }
    }

    private var footerNotice: some View {
        Text(viewModel.nonMedicalNotice)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ensureImmersiveSpaceOpened() async {
        guard !hasOpenedImmersiveSpace else { return }
        hasOpenedImmersiveSpace = true
        _ = await openImmersiveSpace(id: "ImmersiveSpace")
    }
}

#Preview(windowStyle: .plain) {
    MainWindowView()
        .environment(AppViewModel())
}
