//
//  ContentView.swift
//  Meta-Audio
//
//  Created by Unknown Pleasure on 31/07/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject var audio = AudioAnalyzer()
    
    var body: some View {
        MetalView(audio: audio)
            .ignoresSafeArea()
            .onAppear {
                audio.start(vocals: "vocals", bass: "bass", drums: "drums", other: "other", ext: "m4a")
            }
    }
}
