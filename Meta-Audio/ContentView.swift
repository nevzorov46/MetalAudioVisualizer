import SwiftUI

struct ContentView: View {
    @StateObject var audio = AudioAnalyzer()
    
    var body: some View {
        MetalView(audio: audio)
            .ignoresSafeArea()
            .onAppear {
                audio.start(
                    vocals: Constants.vocalsTrackName,
                    bass: Constants.bassTrackName,
                    drums: Constants.drumsTrackName,
                    other: Constants.otherInstrumentsTrackName,
                    ext: Constants.extensionFormat
                )
            }
    }
}
