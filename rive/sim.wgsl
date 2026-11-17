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
    // z: how far it may move in a step, likewise, and still leave the water
    // be: a string eased aside by hand slides through it. w: how far it
    // moves in a step when let go from its furthest pull, which pushes all
    // it can.
    drive: vec4<f32>,
    // At 32 points along it, ends included, four to a vec4: how far it
    // stands aside from its rest line, toward the left of a to b, in scene
    // space as a fraction of the height, now and one step before.
    offsets: array<vec4<f32>, 8>,
    previous: array<vec4<f32>, 8>,
};

struct Sim {
    // Width over height of the scene.
    aspect: f32,
    // 0.5 on an 8 bit target, 0 on a float one.
    bias: f32,
    // How many of `strings` are in use.
    count: f32,
    pad: f32,
    // A drop where a tap fell on the water: x and y in scene space, its
    // radius as a fraction of the height, and how hard it pushes this step,
    // 0 when there is none.
    drop: vec4<f32>,
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

fn sampleAt(values: array<vec4<f32>, 8>, index: i32) -> f32 {
    let i = clamp(index, 0, 31);
    return values[i / 4][i % 4];
}

// Reads one of a string's sampled values at `along`, 0 to 1, between the
// two samples either side.
fn sampled(values: array<vec4<f32>, 8>, along: f32) -> f32 {
    let f = along * 31.0;
    let i = i32(floor(f));
    return mix(sampleAt(values, i), sampleAt(values, i + 1), f - f32(i));
}

// How hard a string pushes the water at p this step. The string sweeps
// through the water where it really is, not along its rest line: every
// point it passed over since the last step is pushed the way it went. A
// fast string crosses many texels in one step, and sweeping, rather than
// pushing where it ends up, leaves no gaps behind it. So the waves leave
// from wherever the string is, and the two corners a pluck leaves carry
// them along it as they run to the ends and back.
fn stringPush(p: vec2<f32>, line: StringDrive) -> f32 {
    let scale = vec2<f32>(sim.aspect, 1.0);
    let pa = (p - line.ends.xy) * scale;
    let ba = (line.ends.zw - line.ends.xy) * scale;
    let size = max(length(ba), 1e-4);
    let along = dot(pa, ba) / (size * size);
    if (along < 0.0 || along > 1.0) {
        return 0.0;
    }
    let across = dot(pa, vec2<f32>(-ba.y, ba.x) / size);
    let now = sampled(line.offsets, along);
    let before = sampled(line.previous, along);
    let moved = now - before;
    let reach = line.drive.y;
    // Inside the band it swept, its edges softened across `reach` centred
    // on them, so the bands of one step and the next meet without a seam:
    // where one fades out the other fades in.
    let low = min(now, before);
    let high = max(now, before);
    let inside = smoothstep(low - 0.5 * reach, low + 0.5 * reach, across)
        - smoothstep(high - 0.5 * reach, high + 0.5 * reach, across);
    // A string eased aside by hand slides through the water; once it moves
    // faster than that it pushes evenly. The band it sweeps is already as
    // wide as it moved, so a harder pluck stirs more water, and a light one
    // still shows.
    let strength = smoothstep(0.0, 0.25, (abs(moved) - line.drive.z) / line.drive.w);
    return inside * strength * sign(moved) * line.drive.x;
}

// How hard a drop pushes the water at p this step: most at its centre,
// falling off smoothly, round on a scene of any shape.
fn dropPush(p: vec2<f32>) -> f32 {
    let d = (p - sim.drop.xy) * vec2<f32>(sim.aspect, 1.0);
    let r = max(sim.drop.z, 1e-4);
    return sim.drop.w * exp(-dot(d, d) / (r * r));
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
    if (sim.drop.w != 0.0) {
        velocity += dropPush(in.scene);
    }

    // Ink is left where the surface moves, and settles slowly. It nears its
    // fullest gradually, so a hard pluck leaves a glow that fades at its
    // edges rather than a flat sheet.
    ink = max(ink * 0.9975, 1.0 - exp(-abs(height) * 0.9));

    // Edges soak the wave up instead of mirroring it.
    let edge = vec2<f32>(min(at, limit - at));
    let soak = clamp(min(edge.x, edge.y) / 12.0, 0.0, 1.0);
    height *= mix(0.9, 1.0, soak);
    velocity *= mix(0.9, 1.0, soak);

    return vec4<f32>(height + sim.bias, velocity + sim.bias, ink, 1.0);
}
