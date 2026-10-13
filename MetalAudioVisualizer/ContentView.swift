import SwiftUI

struct ContentView: View {
    @StateObject private var audio = AudioAnalyzer()

    var body: some View {
        MetalView(audio: audio)
            .ignoresSafeArea()
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .onAppear {
                audio.start()
            }
    }
}
