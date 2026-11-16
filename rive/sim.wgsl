// One step of the medium: a damped wave field plus the ink it leaves behind.
//
// State texel: r = height, g = velocity, b = ink, a = unused.
// On a float target the values are stored as they are. On an 8 bit target
// height and velocity are stored around 0.5, which `bias` undoes.
//
// Neighbours are read with textureLoad at the fragment's own pixel, so a
// texel always reads the storage it was written to, whichever way up the
// backend keeps a render target. Positions in the scene come from clip
// space instead, which every backend agrees on.

// One string shaking the surface under it.
struct StringDrive {
    // Its two ends in scene space, 0 to 1 with y down: a.xy then b.xy.
    ends: vec4<f32>,
    // x: how hard its motion pushes the surface. y: how far to either side
    // of it the push reaches, in scene space as a fraction of the height.
    drive: vec4<f32>,
    // How fast it moves at 16 points along it, ends included, as a fraction
    // of the speed of a full pull's main swing; four to a vec4.
    speeds: array<vec4<f32>, 4>,
};

struct Sim {
    // Width over height of the scene.
    aspect: f32,
    // 0.5 on an 8 bit target, 0 on a float one.
    bias: f32,
    // How many of `strings` are in use.
    count: f32,
    pad: f32,
    strings: array<StringDrive, 12>,
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

fn sampleAt(values: array<vec4<f32>, 4>, index: i32) -> f32 {
    let i = clamp(index, 0, 15);
    return values[i / 4][i % 4];
}

// Reads one of a string's sampled values at `along`, 0 to 1, between the
// two samples either side.
fn sampled(values: array<vec4<f32>, 4>, along: f32) -> f32 {
    let f = along * 15.0;
    let i = i32(floor(f));
    return mix(sampleAt(values, i), sampleAt(values, i + 1), f - f32(i));
}

// How strongly a string pushes at p. The water along the string's rest
// line is pushed as hard as the string above it is moving there, so the
// waves follow the string's own motion: they start where it was plucked,
// and the two corners the pluck leaves carry them out to both ends.
fn stringPush(p: vec2<f32>, line: StringDrive) -> f32 {
    let scale = vec2<f32>(sim.aspect, 1.0);
    let pa = (p - line.ends.xy) * scale;
    let ba = (line.ends.zw - line.ends.xy) * scale;
    let size = max(length(ba), 1e-4);
    let along = dot(pa, ba) / (size * size);
    if (along < 0.0 || along > 1.0) {
        return 0.0;
    }
    let distance = abs(dot(pa, vec2<f32>(-ba.y, ba.x) / size));
    let speed = sampled(line.speeds, along);
    return smoothstep(line.drive.y, 0.0, distance) * speed * line.drive.x;
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
    velocity = (velocity + laplacian * 0.25) * 0.996;
    height = (height + velocity) * 0.999;

    let count = i32(sim.count);
    for (var i = 0; i < 12; i++) {
        if (i >= count) {
            break;
        }
        velocity += stringPush(in.scene, sim.strings[i]);
    }

    // Ink is left where the surface moves, and settles slowly.
    ink = max(ink * 0.9975, min(abs(height) * 0.8, 1.0));

    // Edges soak the wave up instead of mirroring it.
    let edge = vec2<f32>(min(at, limit - at));
    let soak = clamp(min(edge.x, edge.y) / 12.0, 0.0, 1.0);
    height *= mix(0.9, 1.0, soak);
    velocity *= mix(0.9, 1.0, soak);

    return vec4<f32>(height + sim.bias, velocity + sim.bias, ink, 1.0);
}
