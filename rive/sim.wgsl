// One step of the medium: a damped wave field plus the ink it leaves behind.
//
// State texel: r = height, g = velocity, b = ink, a = unused.
// On a float target the values are stored as they are. On an 8 bit target
// height and velocity are stored around 0.5, which `bias` and `gain` undo.
//
// Neighbours are read with textureLoad at the fragment's own pixel, so a
// texel always reads the storage it was written to, whichever way up the
// backend keeps a render target. Positions in the scene come from clip
// space instead, which every backend agrees on.

struct Sim {
    // Pointer in scene space, 0 to 1 with y down, and where it was last step.
    pointer: vec2<f32>,
    previous: vec2<f32>,
    // How hard the pointer pushes this step; 0 when it is up.
    strength: f32,
    // Pointer radius in scene space, as a fraction of the height.
    radius: f32,
    // 0.5 on an 8 bit target, 0 on a float one.
    bias: f32,
    // Width over height of the scene.
    aspect: f32,
};

@group(0) @binding(0) var<uniform> sim: Sim;
@group(0) @binding(1) var state: texture_2d<f32>;

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) scene: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) index: u32) -> VertexOutput {
    var corners = array<vec2<f32>, 3>(vec2(-1.0, -1.0), vec2(3.0, -1.0), vec2(-1.0, 3.0));
    let clip = corners[index];
    var out: VertexOutput;
    out.position = vec4<f32>(clip, 0.0, 1.0);
    out.scene = vec2<f32>(clip.x * 0.5 + 0.5, 0.5 - clip.y * 0.5);
    return out;
}

fn load(at: vec2<i32>, limit: vec2<i32>) -> vec4<f32> {
    return textureLoad(state, clamp(at, vec2<i32>(0, 0), limit), 0);
}

// Distance from p to the segment a-b, in scene space corrected for aspect.
fn segmentDistance(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let scale = vec2<f32>(sim.aspect, 1.0);
    let pa = (p - a) * scale;
    let ba = (b - a) * scale;
    let t = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * t);
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let size = vec2<i32>(textureDimensions(state));
    let limit = size - vec2<i32>(1, 1);
    let at = vec2<i32>(in.position.xy);

    let centre = load(at, limit);
    let left = load(at + vec2<i32>(-1, 0), limit).r - sim.bias;
    let right = load(at + vec2<i32>(1, 0), limit).r - sim.bias;
    let up = load(at + vec2<i32>(0, -1), limit).r - sim.bias;
    let down = load(at + vec2<i32>(0, 1), limit).r - sim.bias;

    var height = centre.r - sim.bias;
    var velocity = centre.g - sim.bias;
    var ink = centre.b;

    // Wave equation, explicit; 0.25 keeps it inside the stability limit.
    let laplacian = left + right + up + down - 4.0 * height;
    velocity = (velocity + laplacian * 0.25) * 0.992;
    height = (height + velocity) * 0.998;

    // The pointer pushes the surface down along its last stroke.
    if (sim.strength > 0.0) {
        let distance = segmentDistance(in.scene, sim.previous, sim.pointer);
        let push = smoothstep(sim.radius, 0.0, distance) * sim.strength;
        velocity -= push;
    }

    // Ink is left where the surface moves, and settles slowly.
    ink = max(ink * 0.994, min(abs(height) * 1.2, 1.0));

    // Edges soak the wave up instead of mirroring it.
    let edge = vec2<f32>(min(at, limit - at));
    let soak = clamp(min(edge.x, edge.y) / 12.0, 0.0, 1.0);
    height *= mix(0.9, 1.0, soak);
    velocity *= mix(0.9, 1.0, soak);

    return vec4<f32>(height + sim.bias, velocity + sim.bias, ink, 1.0);
}
