import SwiftUI
import RealityKit

struct ImmersiveOverlayView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        RealityView { content in
            viewModel.placementController.prepareScene(content: content)
        }
        .overlay(alignment: .bottom) {
            Text(viewModel.nonMedicalNotice)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(8)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 24)
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveOverlayView()
        .environment(AppViewModel())
}
