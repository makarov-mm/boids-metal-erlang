//  BoidsMetalApp.swift — BoidsMetal
//  SwiftUI shell around an MTKView. The simulation is NOT here —
//  it lives in an Erlang node; this app only renders frames.
//
//  Keys:  K — chaos (kill a random boid process on the server)
//         B — spawn one more boid
//
//  Run the server first:
//    erl -pa ebin -noshell -eval "flock_server:start(200, 4040)"

import SwiftUI
import MetalKit

@main
struct BoidsMetalApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 800)
        }
    }
}

struct ContentView: View {
    @StateObject private var client = FlockClient()
    @State private var keyMonitor: Any?

    var body: some View {
        ZStack(alignment: .topLeading) {
            MetalView(client: client)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 4) {
                Text("boids: \(client.boidCount)   [\(client.status)]")
                Text("K — kill a random boid process   B — spawn one")
                    .foregroundStyle(.secondary)
            }
            .font(.system(.body, design: .monospaced))
            .padding(10)
        }
        .onAppear {
            client.connect()
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "k": client.sendChaos(); return nil
                case "b": client.sendSpawn(); return nil
                default:  return event
                }
            }
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        }
    }
}

struct MetalView: NSViewRepresentable {
    let client: FlockClient

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        if let renderer = Renderer(mtkView: view) {
            context.coordinator.renderer = renderer
            client.onFrame = { payload, count in
                renderer.update(payload: payload, count: count)
            }
        }
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderer: Renderer?
    }
}
