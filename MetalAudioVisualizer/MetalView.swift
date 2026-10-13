import MetalKit
import SwiftUI

struct MetalView: UIViewRepresentable {
    let audio: AudioAnalyzer

    func makeCoordinator() -> Renderer { Renderer(audio: audio) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.colorPixelFormat = Renderer.outputPixelFormat
        view.preferredFramesPerSecond = Constants.preferredFramesPerSecond
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
