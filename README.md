# Boids: Erlang backend + Swift/Metal frontend

The simulation lives on the BEAM: every boid is an isolated Erlang process
(`gen_server`) under a supervisor. A macOS app connects over TCP and renders
the flock with Metal instanced drawing. Kill a boid process from the keyboard —
the supervisor restarts it and you watch it respawn on screen.

Zero external dependencies on both sides: pure OTP, pure
Metal/MetalKit/Network.framework.

```
┌────────────────────────────┐        ┌───────────────────────────┐
│  Erlang node               │  TCP   │  macOS app                │
│  boid_sup                  │ ─────► │  FlockClient (Network)    │
│   ├─ boid #1 (gen_server)  │ 60 Hz  │  Renderer (Metal,         │
│   ├─ boid #2               │ frames │   instanced triangles)    │
│   └─ ...                   │ ◄───── │  keys: K=chaos, B=spawn   │
│  flock_server (gen_tcp)    │  cmds  │                           │
└────────────────────────────┘        └───────────────────────────┘
```

## Wire protocol

Little-endian, one frame per tick:

```
frame = count :: uint32
      , count * { x, y, vx, vy } :: 4 * float32     (16 bytes per boid)
```

The layout matches MSL `float4` exactly, so the frontend memcpy's the
payload straight into the Metal instance buffer. No parsing, no conversion.

Commands from client to server, single bytes:
`0x01` chaos (kill a random boid process), `0x02` spawn one more.

Coordinates are normalized to `[0,1] x [0,1]`; the renderer letterboxes.

## Run the server (tested on OTP 25)

```bash
cd erlang
mkdir -p ebin
erlc -o ebin src/*.erl
erl -pa ebin -noshell -eval "flock_server:start(200, 4040)"
```

`test_client.py` in the repo root emulates the renderer and verifies the
protocol, flock dynamics, and supervisor restarts without needing a Mac.

## Build the macOS app

1. Xcode → New Project → macOS → **App**, product name `BoidsMetal`,
   interface SwiftUI.
2. Delete the generated `ContentView.swift` / `BoidsMetalApp.swift`, drag in
   the four files from `swift/BoidsMetal/`:
   `BoidsMetalApp.swift`, `Renderer.swift`, `FlockClient.swift`, `Shaders.metal`.
3. **Important:** target → Signing & Capabilities → App Sandbox → check
   **Outgoing Connections (Client)**. Without it the sandbox silently blocks
   the TCP connection.
4. Start the Erlang server, then Run.

## The demo

Press **K**: a `exit(Pid, kill)` is executed on a random boid process on the
server. The supervisor restarts it within microseconds and the boid visibly
teleports to a fresh random position. Nothing in the code handles this case —
fault tolerance is a property of the runtime, not a feature of the app.

Press **B** to grow the flock live; the frame size adapts automatically
(the frontend reads `count` from every frame).
