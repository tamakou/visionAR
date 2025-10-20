import SwiftUI

@main
struct VisionARApp: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environment(viewModel)
        }
        .defaultSize(width: 640, height: 480)

        ImmersiveSpace(id: "ImmersiveSpace") {
            ImmersiveOverlayView()
                .environment(viewModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
