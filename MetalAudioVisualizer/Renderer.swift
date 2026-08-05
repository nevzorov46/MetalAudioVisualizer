import MetalKit
import simd

class Renderer: NSObject, MTKViewDelegate {
    let device = MTLCreateSystemDefaultDevice()!
    var queue: MTLCommandQueue!
    var pipeline: MTLRenderPipelineState!
    var startTime = Date()
    var audio: AudioAnalyzer
    
    var diskVertexBuffer: MTLBuffer!
    var diskVertexCount = 0
    var spikeVertexBuffer: MTLBuffer!
    var spikeVertexCount = 0
    
    let numSpikes = Constants.numberOfSpikes
    
    init(audio: AudioAnalyzer) {
        self.audio = audio
        super.init()
        queue = device.makeCommandQueue()
        let library = device.makeDefaultLibrary()!
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "vertexShader")
        desc.fragmentFunction = library.makeFunction(name: "fragmentShader")
        desc.colorAttachments[0].pixelFormat = .rgba16Float
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].rgbBlendOperation = .add
        desc.colorAttachments[0].sourceRGBBlendFactor = .one
        desc.colorAttachments[0].destinationRGBBlendFactor = .one
        pipeline = try! device.makeRenderPipelineState(descriptor: desc)
        
        buildGeometry()
    }
    
    private func buildGeometry() {
        var disk: [SIMD2<Float>] = []
        let diskPoints = Constants.numberOfSpikes
        for i in 0...diskPoints {
            let angle = Float(i) / Float(diskPoints) * 2 * .pi
            disk.append(SIMD2(cos(angle), sin(angle)))
            disk.append(SIMD2(0, 0))
        }
        diskVertexCount = disk.count
        diskVertexBuffer = device.makeBuffer(bytes: disk, length: disk.count * MemoryLayout<SIMD2<Float>>.stride, options: [])
        
        var spikes: [SIMD2<Float>] = []
        let halfWidth: Float = Constants.halfWidth
        
        for i in 0..<numSpikes {
            let angle = Float(i) / Float(numSpikes) * 2 * .pi
            let dir = SIMD2<Float>(cos(angle), sin(angle))
            let perp = SIMD2<Float>(-dir.y, dir.x)
            spikes.append(dir + perp * halfWidth) // 0: inner-left
            spikes.append(dir - perp * halfWidth) // 1: inner-right
            spikes.append(dir + perp * halfWidth) // 2: outer-left
            spikes.append(dir - perp * halfWidth) // 3: outer-right
        }
        spikeVertexCount = spikes.count
        spikeVertexBuffer = device.makeBuffer(bytes: spikes, length: spikes.count * MemoryLayout<SIMD2<Float>>.stride, options: [])
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else { return }
        
        struct Uniforms {
            var time: Float
            var bass: Float
            var drums: Float
            var vocals: Float
            var other: Float
        }
        var uniforms = Uniforms(
            time: Float(Date().timeIntervalSince(startTime)),
            bass: audio.bassLevel,
            drums: audio.drumsLevel,
            vocals: audio.vocalsLevel,
            other: audio.otherLevel
        )
        
        let buffer = queue.makeCommandBuffer()!
        let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)!
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
        
        encoder.setVertexBuffer(diskVertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes([Int32(0)], length: 4, index: 2) // mode 0 = disk
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.size,
            index: 0
        )
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: diskVertexCount)
        
        encoder.setVertexBuffer(spikeVertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes([Int32(1)], length: 4, index: 2) // mode 1 = spikes
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: spikeVertexCount)
        
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
