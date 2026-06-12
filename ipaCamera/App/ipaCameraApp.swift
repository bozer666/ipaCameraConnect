import SwiftUI

@main
struct ipaCameraApp: App {
    @StateObject private var cameraViewModel = CameraViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cameraViewModel)
                .onAppear {
                    cameraViewModel.start()
                }
        }
    }
}
