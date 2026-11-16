// Turns the medium's state into what is seen: dark water lit from its
// slope, with ink glowing from cold to hot by how hard it was struck.
//
// The state is sampled at this fragment's own position in the canvas, as a
// fraction of the canvas, so it lines up with the state texture's storage on
// every backend.

struct Show {
    // Size of the canvas in pixels.
    canvas: vec2<f32>,
    // 0.5 on an 8 bit state, 0 on a float one.
    bias: f32,
    // 1 draws the diagnostic markers.
    debug: f32,
    // Feature bits for the diagnostic strip: 1 half float, 2 float.
    features: f32,
    pad0: f32,
    pad1: f32,
    pad2: f32,
};

@group(0) @binding(0) var<uniform> show: Show;
@group(0) @binding(1) var state: texture_2d<f32>;
@group(0) @binding(2) var stateSampler: sampler;

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

fn heightAt(uv: vec2<f32>) -> f32 {
    return textureSampleLevel(state, stateSampler, uv, 0.0).r - show.bias;
}

// Cold to hot: deep blue, cyan, amber, near white.
fn inkColor(amount: f32) -> vec3<f32> {
    let cold = vec3<f32>(0.05, 0.35, 0.95);
    let cool = vec3<f32>(0.10, 0.85, 0.90);
    let warm = vec3<f32>(1.00, 0.62, 0.15);
    let hot = vec3<f32>(1.00, 0.95, 0.85);
    let a = clamp(amount, 0.0, 1.0);
    if (a < 0.33) {
        return mix(cold, cool, a / 0.33);
    }
    if (a < 0.66) {
        return mix(cool, warm, (a - 0.33) / 0.33);
    }
    return mix(warm, hot, (a - 0.66) / 0.34);
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let uv = in.position.xy / show.canvas;
    let texel = 1.0 / vec2<f32>(textureDimensions(state));
    let here = textureSampleLevel(state, stateSampler, uv, 0.0);
    let ink = here.b;

    // Slope of the surface, for a light glancing across it.
    let dx = heightAt(uv + vec2<f32>(texel.x, 0.0)) - heightAt(uv - vec2<f32>(texel.x, 0.0));
    let dy = heightAt(uv + vec2<f32>(0.0, texel.y)) - heightAt(uv - vec2<f32>(0.0, texel.y));
    let normal = normalize(vec3<f32>(-dx * 6.0, -dy * 6.0, 1.0));
    let light = normalize(vec3<f32>(-0.4, -0.6, 0.7));
    let glance = pow(max(dot(normal, light), 0.0), 24.0);

    let water = vec3<f32>(0.020, 0.028, 0.045);
    var color = water + vec3<f32>(0.25, 0.32, 0.45) * glance * 0.6;
    color += inkColor(ink) * ink * ink * 1.4;

    if (show.debug > 0.5) {
        // A white square in the scene's top left corner shows which way up
        // the scene arrives; a strip beside it shows the feature bits.
        if (in.scene.x < 0.02 && in.scene.y < 0.035) {
            color = vec3<f32>(1.0, 1.0, 1.0);
        }
        if (in.scene.y < 0.035 && in.scene.x > 0.03 && in.scene.x < 0.05) {
            color = select(vec3<f32>(0.6, 0.0, 0.0), vec3<f32>(0.0, 0.8, 0.2), show.features >= 1.0);
        }
        if (in.scene.y < 0.035 && in.scene.x > 0.06 && in.scene.x < 0.08) {
            color = select(vec3<f32>(0.6, 0.0, 0.0), vec3<f32>(0.0, 0.8, 0.2), show.features >= 2.0);
        }
    }

    return vec4<f32>(color, 1.0);
}
