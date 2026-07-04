//  FlockClient.swift — BoidsMetal
//  TCP client for the Erlang flock_server.
//
//  Wire protocol (little-endian, exactly what Metal wants):
//    frame = count :: UInt32
//          , count * 16 bytes of float32 {x, y, vx, vy}
//
//  Commands to the server (single bytes):
//    0x01 — chaos: kill a random boid process
//    0x02 — spawn one more boid

import Foundation
import Network

final class FlockClient: ObservableObject {

    @Published var boidCount: Int = 0
    @Published var status: String = "connecting..."

    /// Called on an arbitrary queue with the raw instance data
    /// (count * 16 bytes, ready for memcpy into a Metal buffer).
    var onFrame: ((Data, Int) -> Void)?

    private var connection: NWConnection?
    private var buffer = Data()
    private let queue = DispatchQueue(label: "flock.net")

    func connect(host: String = "127.0.0.1", port: UInt16 = 4040) {
        let conn = NWConnection(host: NWEndpoint.Host(host),
                                port: NWEndpoint.Port(rawValue: port)!,
                                using: .tcp)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:            self?.status = "connected"
                case .waiting(let e):   self?.status = "waiting: \(e)"
                case .failed(let e):    self?.status = "failed: \(e)"
                case .cancelled:        self?.status = "cancelled"
                default:                break
                }
            }
        }

        conn.start(queue: queue)
        receive()
    }

    func sendChaos() { send(byte: 0x01) }
    func sendSpawn() { send(byte: 0x02) }

    private func send(byte: UInt8) {
        connection?.send(content: Data([byte]),
                         completion: .contentProcessed { _ in })
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1,
                            maximumLength: 1 << 16) { [weak self] data, _, isDone, error in
            guard let self else { return }
            if let data { self.buffer.append(data) }
            self.drainFrames()
            if isDone || error != nil {
                DispatchQueue.main.async { self.status = "disconnected" }
                return
            }
            self.receive()
        }
    }

    /// Parse every complete frame currently in the buffer,
    /// forward only the most recent one (no point rendering stale frames).
    private func drainFrames() {
        var latest: (Data, Int)? = nil
        while buffer.count >= 4 {
            let count = buffer.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self).littleEndian
            }
            let frameBytes = 4 + Int(count) * 16
            guard buffer.count >= frameBytes else { break }
            latest = (buffer.subdata(in: 4 ..< frameBytes), Int(count))
            buffer.removeSubrange(0 ..< frameBytes)
        }
        if let (payload, count) = latest {
            onFrame?(payload, count)
            DispatchQueue.main.async { self.boidCount = count }
        }
    }
}
