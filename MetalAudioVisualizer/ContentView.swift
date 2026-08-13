import SwiftUI

struct ContentView: View {
    @StateObject var audio = AudioAnalyzer()

    var body: some View {
        MetalView(audio: audio)
            .ignoresSafeArea()
            .onAppear {
                audio.start()
            }
    }
}
