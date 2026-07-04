//  Renderer.swift — BoidsMetal
//  MTKViewDelegate. The instance buffer is filled byte-for-byte with
//  the network payload: the Erlang wire format {x, y, vx, vy} as
//  float32-little matches MSL float4 layout exactly.

import Foundation
import Metal
import MetalKit

final class Renderer: NSObject, MTKViewDelegate {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    private let maxBoids = 8192
    private let instanceBuffer: MTLBuffer
    private var instanceCount = 0
    private let lock = NSLock()

    init?(mtkView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vfn = library.makeFunction(name: "boid_vertex"),
              let ffn = library.makeFunction(name: "boid_fragment")
        else { return nil }

        self.device = device
        self.commandQueue = queue

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: desc),
              let buffer = device.makeBuffer(length: maxBoids * MemoryLayout<SIMD4<Float>>.stride,
                                             options: .storageModeShared)
        else { return nil }

        self.pipeline = pipeline
        self.instanceBuffer = buffer

        super.init()

        mtkView.device = device
        mtkView.delegate = self
        mtkView.clearColor = MTLClearColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1)
        mtkView.preferredFramesPerSecond = 60
    }

    /// Called from the network queue with raw frame bytes.
    func update(payload: Data, count: Int) {
        let n = min(count, maxBoids)
        lock.lock()
        payload.withUnsafeBytes { src in
            instanceBuffer.contents().copyMemory(from: src.baseAddress!,
                                                 byteCount: n * 16)
        }
        instanceCount = n
        lock.unlock()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = commandQueue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)
        else { return }

        lock.lock()
        let count = instanceCount
        lock.unlock()

        if count > 0 {
            let w = Float(view.drawableSize.width)
            let h = Float(view.drawableSize.height)
            let side = min(w, h)
            var viewScale = SIMD2<Float>(side / w, side / h)

            enc.setRenderPipelineState(pipeline)
            enc.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
            enc.setVertexBytes(&viewScale,
                               length: MemoryLayout<SIMD2<Float>>.stride,
                               index: 1)
            enc.drawPrimitives(type: .triangle,
                               vertexStart: 0,
                               vertexCount: 3,
                               instanceCount: count)
        }

        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}
