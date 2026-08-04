//
//  MetalView.swift
//  Meta-Audio
//
//  Created by Unknown Pleasure on 31/07/2026.
//

import Combine
import UIKit
import Foundation
import SwiftUI
import MetalKit

struct MetalView: UIViewRepresentable {
    @ObservedObject var audio: AudioAnalyzer
    
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.colorPixelFormat = .rgba16Float
        view.device = MTLCreateSystemDefaultDevice()
        view.delegate = context.coordinator
        view.preferredFramesPerSecond = 60
        return view
    }
    func updateUIView(_ uiView: MTKView, context: Context) {}
    func makeCoordinator() -> Renderer { Renderer(audio: audio) }
}
