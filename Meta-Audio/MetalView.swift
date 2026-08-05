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
        view.preferredFramesPerSecond = Constants.preferredFramesPerSecond
        return view
    }
    func updateUIView(_ uiView: MTKView, context: Context) {}
    func makeCoordinator() -> Renderer { Renderer(audio: audio) }
}
