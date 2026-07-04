#!/usr/bin/env python3
"""Test client emulating the Swift renderer: reads frames, checks the
binary protocol, sends chaos/spawn commands, verifies flock dynamics."""
import socket, struct, math, time

def read_exact(s, n):
    buf = b""
    while len(buf) < n:
        chunk = s.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("closed")
        buf += chunk
    return buf

def read_frame(s):
    count = struct.unpack("<I", read_exact(s, 4))[0]
    data = read_exact(s, count * 16)
    boids = [struct.unpack_from("<4f", data, i * 16) for i in range(count)]
    return boids

def avg_nn_dist(boids):
    total = 0.0
    for i, (x, y, _, _) in enumerate(boids):
        best = 10.0
        for j, (x2, y2, _, _) in enumerate(boids):
            if i == j: continue
            d = math.hypot(x - x2, y - y2)
            if d < best: best = d
        total += best
    return total / len(boids)

s = socket.create_connection(("127.0.0.1", 4040))
f0 = read_frame(s)
print(f"frame ok: {len(f0)} boids")

bad = [b for b in f0 for v in b if not math.isfinite(v)]
in_range = all(0.0 <= b[0] <= 1.0 and 0.0 <= b[1] <= 1.0 for b in f0)
print(f"all finite: {not bad}, positions in [0,1]: {in_range}")

d_start = avg_nn_dist(f0)
# let it fly ~5 seconds
last = f0
t_end = time.time() + 5
frames = 1
while time.time() < t_end:
    last = read_frame(s)
    frames += 1
d_end = avg_nn_dist(last)
speeds = [math.hypot(vx, vy) for _, _, vx, vy in last]
print(f"frames in 5s: {frames} (~{frames/5:.0f} fps)")
print(f"avg nearest-neighbour dist: {d_start:.4f} -> {d_end:.4f} (flocking => should drop)")
print(f"speed min/max: {min(speeds):.5f}/{max(speeds):.5f} (clamp 0.003..0.008)")
in_range2 = all(0.0 <= b[0] <= 1.0 and 0.0 <= b[1] <= 1.0 for b in last)
finite2 = all(math.isfinite(v) for b in last for v in b)
print(f"after 5s: finite={finite2}, in range={in_range2}")

n_before = len(last)
s.sendall(b"\x01")           # chaos
time.sleep(0.2)
n_after = len(read_frame(s))
print(f"chaos: {n_before} -> {n_after} boids (supervisor restart)")

s.sendall(b"\x02")           # spawn extra
time.sleep(0.2)
n_spawn = len(read_frame(s))
print(f"spawn: -> {n_spawn} boids")
s.close()
print("ALL CHECKS DONE")
