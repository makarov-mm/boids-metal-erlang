//  Shaders.metal — BoidsMetal
//  Instanced rendering: one triangle per boid, rotated to its heading.
//  Instance data arrives from the Erlang server as float4 {x, y, vx, vy}
//  and is memcpy'd into the buffer untouched — the wire format IS the
//  GPU format.

#include <metal_stdlib>
using namespace metal;

struct VOut {
    float4 position [[position]];
    float4 color;
};

vertex VOut boid_vertex(uint vid                     [[vertex_id]],
                        uint iid                     [[instance_id]],
                        device const float4 *boids   [[buffer(0)]],
                        constant float2 &viewScale   [[buffer(1)]])
{
    // Triangle in model space, nose pointing along +X.
    const float2 tri[3] = {
        float2( 1.6,  0.0),
        float2(-1.0,  0.8),
        float2(-1.0, -0.8)
    };

    float4 b   = boids[iid];          // x, y, vx, vy
    float2 vel = b.zw;
    float  ang = atan2(vel.y, vel.x);
    float  c   = cos(ang);
    float  s   = sin(ang);

    const float size = 0.007;
    float2 p  = tri[vid] * size;
    float2 rp = float2(p.x * c - p.y * s,
                       p.x * s + p.y * c);

    float2 world = b.xy + rp;               // normalized [0,1]^2
    float2 clip  = world * 2.0 - 1.0;
    clip.y = -clip.y;                        // screen y up
    clip *= viewScale;                       // letterbox: keep world square

    float speed = clamp(length(vel) / 0.008, 0.0, 1.0);

    VOut out;
    out.position = float4(clip, 0.0, 1.0);
    // slow = deep blue, fast = warm white
    out.color = float4(0.25 + 0.75 * speed,
                       0.45 + 0.45 * speed,
                       0.95,
                       1.0);
    return out;
}

fragment float4 boid_fragment(VOut in [[stage_in]])
{
    return in.color;
}
