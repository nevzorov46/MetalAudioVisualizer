import MetalKit
import QuartzCore
import simd

/// Matches `SceneUniforms` in `Scene.metal` — keep the field order in sync.
private struct SceneUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var bandCount: Float
    var levels: SIMD4<Float>
    var beatAges: SIMD4<Float>
    var flow: Float
}

/// Matches `CompositeUniforms` in `PostProcess.metal`.
private struct CompositeUniforms {
    var bloomIntensity: Float
    var time: Float
}

/// Draws each frame in three stages: the scene into an HDR texture, a bloom
/// chain built from it, and a tone-mapped composite onto the screen.
final class Renderer: NSObject, MTKViewDelegate {
    static let outputPixelFormat: MTLPixelFormat = .bgra8Unorm
    private static let hdrPixelFormat: MTLPixelFormat = .rgba16Float

    let device: MTLDevice

    private let audio: AudioAnalyzer
    private let queue: MTLCommandQueue
    private let scenePipeline: MTLRenderPipelineState
    private let downsamplePipeline: MTLRenderPipelineState
    private let upsamplePipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState

    private var sceneTexture: MTLTexture?
    private var bloomMips: [MTLTexture] = []

    /// The spectrum at the playhead, and the eased copy of it that is drawn.
    private var target: [Float]
    private var spectrum: [Float]
    /// Distance the background dust has drifted; it speeds up with loudness.
    private var flow: Float = 0
    private let startTime = CACurrentMediaTime()
    private var lastFrameTime = CACurrentMediaTime()

    init(audio: AudioAnalyzer) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            fatalError("Metal is not available on this device")
        }

        func pipeline(_ fragment: String, format: MTLPixelFormat, additive: Bool = false) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = fragment
            descriptor.vertexFunction = library.makeFunction(name: "fullscreenVertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = format
            if additive {
                descriptor.colorAttachments[0].isBlendingEnabled = true
                descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
                descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
            }
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }

        do {
            scenePipeline = try pipeline("sceneFragment", format: Self.hdrPixelFormat)
            downsamplePipeline = try pipeline("downsampleFragment", format: Self.hdrPixelFormat)
            upsamplePipeline = try pipeline("upsampleFragment", format: Self.hdrPixelFormat, additive: true)
            compositePipeline = try pipeline("compositeFragment", format: Self.outputPixelFormat)
        } catch {
            fatalError("Failed to build render pipelines: \(error)")
        }

        self.device = device
        self.queue = queue
        self.audio = audio
        self.target = [Float](repeating: 0, count: AudioAnalyzer.spectrumSize)
        self.spectrum = target
        super.init()
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = queue.makeCommandBuffer() else { return }

        let screen = drawable.texture
        if sceneTexture?.width != screen.width || sceneTexture?.height != screen.height {
            makeRenderTargets(width: screen.width, height: screen.height)
        }
        guard let sceneTexture, let bloom = bloomMips.first else { return }

        let now = CACurrentMediaTime()
        let deltaTime = Float(now - lastFrameTime)
        lastFrameTime = now
        let time = Float(now - startTime)

        audio.read(into: &target)
        easeSpectrum(deltaTime: deltaTime)
        let levels = stemLevels()
        flow += deltaTime * (Constants.dustDrift + Constants.dustBoost * levels.sum() / 4)

        // 1. Scene.
        var scene = SceneUniforms(
            resolution: SIMD2(Float(screen.width), Float(screen.height)),
            time: time,
            bandCount: Float(Constants.bandCount),
            levels: levels,
            beatAges: SIMD4(audio.beatAges(count: 4)),
            flow: flow
        )
        draw(into: sceneTexture, using: scenePipeline, in: commandBuffer) { encoder in
            encoder.setFragmentBytes(&scene, length: MemoryLayout<SceneUniforms>.stride, index: 0)
            encoder.setFragmentBytes(spectrum, length: spectrum.count * MemoryLayout<Float>.stride, index: 1)
        }

        // 2. Bloom: shrink the scene step by step, then grow it back,
        //    adding every level's blur on top of the sharper one below.
        var source = sceneTexture
        for mip in bloomMips {
            draw(into: mip, using: downsamplePipeline, in: commandBuffer) { encoder in
                encoder.setFragmentTexture(source, index: 0)
            }
            source = mip
        }
        for level in stride(from: bloomMips.count - 1, to: 0, by: -1) {
            draw(into: bloomMips[level - 1], using: upsamplePipeline, keepingContents: true, in: commandBuffer) { encoder in
                encoder.setFragmentTexture(bloomMips[level], index: 0)
            }
        }

        // 3. Composite onto the screen.
        var composite = CompositeUniforms(bloomIntensity: Constants.bloomIntensity, time: time)
        draw(into: screen, using: compositePipeline, in: commandBuffer) { encoder in
            encoder.setFragmentTexture(sceneTexture, index: 0)
            encoder.setFragmentTexture(bloom, index: 1)
            encoder.setFragmentBytes(&composite, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: Passes

    /// Runs one full-screen pass of `pipeline` into `target`.
    private func draw(into target: MTLTexture,
                      using pipeline: MTLRenderPipelineState,
                      keepingContents: Bool = false,
                      in commandBuffer: MTLCommandBuffer,
                      configure: (MTLRenderCommandEncoder) -> Void) {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = keepingContents ? .load : .dontCare
        descriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.setRenderPipelineState(pipeline)
        configure(encoder)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func makeRenderTargets(width: Int, height: Int) {
        func texture(width: Int, height: Int) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: Self.hdrPixelFormat, width: max(width, 1), height: max(height, 1), mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            return device.makeTexture(descriptor: descriptor)
        }

        sceneTexture = texture(width: width, height: height)
        bloomMips = (1...Constants.bloomMipCount).compactMap { level in
            texture(width: width >> level, height: height >> level)
        }
    }

    // MARK: Spectrum

    /// Moves the displayed spectrum toward the one at the playhead:
    /// quickly when a band rises, slowly when it falls.
    private func easeSpectrum(deltaTime: Float) {
        let attack = 1 - exp(-deltaTime / Constants.attackTime)
        let release = 1 - exp(-deltaTime / Constants.releaseTime)

        for index in spectrum.indices {
            let rate = target[index] > spectrum[index] ? attack : release
            spectrum[index] += (target[index] - spectrum[index]) * rate
        }
    }

    /// Average displayed level of each stem.
    private func stemLevels() -> SIMD4<Float> {
        let bandCount = Constants.bandCount
        return SIMD4(AudioAnalyzer.Stem.allCases.map { stem in
            let start = stem.rawValue * bandCount
            return spectrum[start..<start + bandCount].reduce(0, +) / Float(bandCount)
        })
    }
}
