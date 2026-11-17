// The medium: a shader simulation of a dark water surface that carries on
// from frame to frame, shaken by the strings above it.
import { Context } from "rive/host";
import { Renderer } from "rive/renderer";
import { Buffer } from "rive/buffer";
import { Mat2D } from "rive/mat2d";
import { BlendMode } from "rive/paint";
import { ImageSampler, ImageWrap, ImageFilter } from "rive/image";
import {
    GPUBindGroup, GPUBindGroupSampler, GPUBindGroupTexture, GPUBindGroupUBO,
    GPUBuffer, GPUCanvas, GPUColorAttachment, GPUColorTargetDesc, GPUPassDesc,
    GPUPipeline, GPUPipelineDesc, GPUSampler, GPUShaderModule, GPUTexture,
    GPUTextureDesc, GPUTextureView,
} from "rive/gpu";
import { SAMPLES, STRING_STEP } from "./strings";
import {
    BufferUsage, Filter, LoadOp, StoreOp, TextureFormat, WrapMode,
} from "rive/gpu_enums";

/// The most strings the surface listens to at once; sim.wgsl holds the same
/// number.
export const MAX_STRINGS: i32 = 12;

/// Seconds one step of the surface covers, the same as a step of the
/// strings. The simulation runs at a fixed height and step, whatever the
/// screen: a browser can hand over a frame of nearly a second or run at
/// 120 Hz, and the wave must behave the same.
export const STEP: f64 = STRING_STEP;

const SIM_HEIGHT: u32 = 360;
// The scene's shape, the bias, the string count and a spare float, then a
// drop: sim.wgsl's Sim up to its strings.
const HEADER_BYTES: i32 = 32;
// A drop: its radius in points, how hard it pushes each step, and for how
// many steps. Small and soft: an answer to a tap, not a pluck.
const DROP_RADIUS: f64 = 10;
const DROP_PUSH: f64 = 0.02;
const DROP_STEPS: i32 = 8;
// Per string: ends, drive, then SAMPLES offsets now and a step before.
const STRING_BYTES: i32 = 32 + 8 * SAMPLES;
const SIM_BYTES: u32 = <u32>(HEADER_BYTES + STRING_BYTES * MAX_STRINGS);
const SHOW_BYTES: u32 = 32;

export class Medium {
    canvas: GPUCanvas? = null;
    simShader: GPUShaderModule? = null;
    showShader: GPUShaderModule? = null;
    simPipeline: GPUPipeline? = null;
    showPipeline: GPUPipeline? = null;

    // Two copies of the state: each step reads one and writes the other.
    viewA: GPUTextureView? = null;
    viewB: GPUTextureView? = null;
    // readA steps from A into B, readB from B into A.
    simReadA: GPUBindGroup? = null;
    simReadB: GPUBindGroup? = null;
    showReadA: GPUBindGroup? = null;
    showReadB: GPUBindGroup? = null;
    // True when A holds the newest state.
    newestIsA: bool = true;
    cleared: bool = false;

    simUniforms: GPUBuffer? = null;
    showUniforms: GPUBuffer? = null;
    simBytes: ArrayBuffer = Buffer.create(SIM_BYTES);
    showBytes: ArrayBuffer = Buffer.create(SHOW_BYTES);
    stateSampler: GPUSampler? = null;
    imageSampler: ImageSampler = ImageSampler(ImageWrap.clamp, ImageWrap.clamp, ImageFilter.bilinear);

    simPassDesc: GPUPassDesc = new GPUPassDesc();
    simAttachment: GPUColorAttachment = new GPUColorAttachment();
    showPassDesc: GPUPassDesc = new GPUPassDesc();
    showAttachment: GPUColorAttachment = new GPUColorAttachment();

    stateFormat: TextureFormat = TextureFormat.rgba8unorm;
    bias: f64 = 0.5;
    featureBits: f64 = 0;

    width: f64 = 0;
    height: f64 = 0;
    simWidth: u32 = 0;

    // A drop on the water, in layout points, and the steps it still pushes.
    dropX: f64 = 0;
    dropY: f64 = 0;
    dropSteps: i32 = 0;

    /// Makes what does not depend on the size. False when the file lacks a
    /// shader or the host cannot make a canvas.
    setup(context: Context): bool {
        if (this.simShader != null) {
            return true;
        }
        let simShader = context.shader("sim");
        let showShader = context.shader("show");
        let canvas = context.gpuCanvas(0, 0);
        if (simShader == null || showShader == null || canvas == null) {
            context.log("janhyang: no shader or no gpu canvas");
            return false;
        }
        this.simShader = simShader;
        this.showShader = showShader;
        this.canvas = canvas;

        let features = context.features();
        if (features.colorBufferHalfFloat) {
            this.stateFormat = TextureFormat.rgba16float;
            this.bias = 0;
            this.featureBits = features.colorBufferFloat ? 2 : 1;
        }

        this.stateSampler = new GPUSampler(
            Filter.linear, Filter.linear, Filter.nearest,
            WrapMode.clampToEdge, WrapMode.clampToEdge);
        this.simUniforms = new GPUBuffer(BufferUsage.uniform, SIM_BYTES);
        this.showUniforms = new GPUBuffer(BufferUsage.uniform, SHOW_BYTES);

        this.simAttachment.storeOp = StoreOp.store;
        this.simPassDesc.color = [this.simAttachment];
        this.showAttachment.loadOp = LoadOp.clear;
        this.showAttachment.storeOp = StoreOp.store;
        this.showPassDesc.color = [this.showAttachment];
        return true;
    }

    resize(width: f64, height: f64, scale: f64): void {
        this.width = width;
        this.height = height;
        let canvas = this.canvas;
        if (canvas == null || width <= 0 || height <= 0) {
            return;
        }
        canvas.resize(<u32>Math.round(width * scale), <u32>Math.round(height * scale));
        let simWidth = <u32>Math.round(<f64>SIM_HEIGHT * width / height);
        if (simWidth != this.simWidth) {
            this.simWidth = simWidth;
            this.buildState();
        }
    }

    // Makes the two state textures and everything that names them.
    private buildState(): void {
        let canvas = this.canvas;
        let simShader = this.simShader;
        let showShader = this.showShader;
        let simUniforms = this.simUniforms;
        let showUniforms = this.showUniforms;
        let stateSampler = this.stateSampler;
        if (canvas == null || simShader == null || showShader == null
            || simUniforms == null || showUniforms == null || stateSampler == null) {
            return;
        }

        let desc = new GPUTextureDesc();
        desc.width = this.simWidth;
        desc.height = SIM_HEIGHT;
        desc.format = this.stateFormat;
        desc.renderTarget = true;
        let viewA = new GPUTexture(desc).view();
        let viewB = new GPUTexture(desc).view();
        this.viewA = viewA;
        this.viewB = viewB;

        if (this.simPipeline == null) {
            let target = new GPUColorTargetDesc();
            target.format = this.stateFormat;
            let simDesc = new GPUPipelineDesc();
            simDesc.vertexModule = simShader;
            simDesc.fragmentModule = simShader;
            simDesc.colorTargets = [target];
            this.simPipeline = new GPUPipeline(simDesc);

            let screen = new GPUColorTargetDesc();
            screen.format = <TextureFormat>canvas.format;
            let showDesc = new GPUPipelineDesc();
            showDesc.vertexModule = showShader;
            showDesc.fragmentModule = showShader;
            showDesc.colorTargets = [screen];
            this.showPipeline = new GPUPipeline(showDesc);
        }
        let simPipeline = this.simPipeline!;
        let showPipeline = this.showPipeline!;

        let simLayout = simPipeline.getBindGroupLayout(0);
        this.simReadA = new GPUBindGroup(simLayout,
            [new GPUBindGroupUBO(0, simUniforms)],
            [new GPUBindGroupTexture(1, viewA)]);
        this.simReadB = new GPUBindGroup(simLayout,
            [new GPUBindGroupUBO(0, simUniforms)],
            [new GPUBindGroupTexture(1, viewB)]);

        let showLayout = showPipeline.getBindGroupLayout(0);
        this.showReadA = new GPUBindGroup(showLayout,
            [new GPUBindGroupUBO(0, showUniforms)],
            [new GPUBindGroupTexture(1, viewA)],
            [new GPUBindGroupSampler(2, stateSampler)]);
        this.showReadB = new GPUBindGroup(showLayout,
            [new GPUBindGroupUBO(0, showUniforms)],
            [new GPUBindGroupTexture(1, viewB)],
            [new GPUBindGroupSampler(2, stateSampler)]);

        this.newestIsA = true;
        this.cleared = false;
    }

    /// True once there is a surface to step and show.
    get ready(): bool {
        let canvas = this.canvas;
        return canvas != null && canvas.width > 0 && this.viewA != null
            && this.simPipeline != null && this.showPipeline != null;
    }

    /// Records one string for the next `step`: its ends in layout points,
    /// how hard it pushes, how far to either side of it the push reaches in
    /// points, and at SAMPLES points along it how far it stands aside now
    /// and stood aside a step before, in points.
    setString(index: i32, ax: f64, ay: f64, bx: f64, by: f64, drive: f64, reach: f64,
              quiet: f64, full: f64, offsets: StaticArray<f32>, previous: StaticArray<f32>): void {
        if (index < 0 || index >= MAX_STRINGS || this.width <= 0 || this.height <= 0) {
            return;
        }
        let bytes = this.simBytes;
        let at = HEADER_BYTES + index * STRING_BYTES;
        Buffer.writef32(bytes, at, ax / this.width);
        Buffer.writef32(bytes, at + 4, ay / this.height);
        Buffer.writef32(bytes, at + 8, bx / this.width);
        Buffer.writef32(bytes, at + 12, by / this.height);
        Buffer.writef32(bytes, at + 16, drive);
        Buffer.writef32(bytes, at + 20, reach / this.height);
        Buffer.writef32(bytes, at + 24, quiet / this.height);
        Buffer.writef32(bytes, at + 28, full / this.height);
        for (let i = 0; i < SAMPLES; i++) {
            Buffer.writef32(bytes, at + 32 + i * 4, <f64>offsets[i] / this.height);
            Buffer.writef32(bytes, at + 32 + (SAMPLES + i) * 4, <f64>previous[i] / this.height);
        }
    }

    /// Lets a drop fall on the water at a point in layout points: a small
    /// ring answering a tap on empty water.
    drop(x: f64, y: f64): void {
        this.dropX = x;
        this.dropY = y;
        this.dropSteps = DROP_STEPS;
    }

    /// Advances the surface one STEP under the first `count` recorded
    /// strings. Call it while drawing.
    step(count: i32): void {
        let canvas = this.canvas;
        let simPipeline = this.simPipeline;
        let viewA = this.viewA;
        let viewB = this.viewB;
        if (canvas == null || simPipeline == null || viewA == null || viewB == null) {
            return;
        }
        let attachment = this.simAttachment;

        // A new state starts level: height and velocity at rest, no ink.
        if (!this.cleared) {
            let rest = <f32>this.bias;
            attachment.loadOp = LoadOp.clear;
            attachment.clearR = rest;
            attachment.clearG = rest;
            attachment.clearB = 0;
            attachment.clearA = 1;
            attachment.view = viewA;
            canvas.beginRenderPass(this.simPassDesc).finish();
            attachment.view = viewB;
            canvas.beginRenderPass(this.simPassDesc).finish();
            this.cleared = true;
        }

        let bytes = this.simBytes;
        Buffer.writef32(bytes, 0, this.height > 0 ? this.width / this.height : 1);
        Buffer.writef32(bytes, 4, this.bias);
        Buffer.writef32(bytes, 8, <f64>count);
        let dropping = this.dropSteps > 0 && this.width > 0 && this.height > 0;
        Buffer.writef32(bytes, 16, dropping ? this.dropX / this.width : 0);
        Buffer.writef32(bytes, 20, dropping ? this.dropY / this.height : 0);
        Buffer.writef32(bytes, 24, dropping ? DROP_RADIUS / this.height : 0);
        Buffer.writef32(bytes, 28, dropping ? DROP_PUSH : 0);
        if (dropping) {
            this.dropSteps--;
        }
        this.simUniforms!.update(0, bytes);

        attachment.loadOp = LoadOp.dontCare;
        attachment.view = this.newestIsA ? viewB : viewA;
        let pass = canvas.beginRenderPass(this.simPassDesc);
        pass.setViewport(0, 0, <f32>this.simWidth, <f32>SIM_HEIGHT);
        pass.setPipeline(simPipeline);
        pass.setBindGroup(0, this.newestIsA ? this.simReadA! : this.simReadB!);
        pass.draw(3);
        pass.finish();
        this.newestIsA = !this.newestIsA;
    }

    /// Draws the surface as it now stands. `debug` of 1 adds the markers
    /// that show which way up the scene arrives and what the GPU offers.
    show(renderer: Renderer, debug: f64): void {
        let canvas = this.canvas;
        let showPipeline = this.showPipeline;
        if (canvas == null || showPipeline == null || canvas.width == 0) {
            return;
        }
        let bytes = this.showBytes;
        Buffer.writef32(bytes, 0, <f64>canvas.width);
        Buffer.writef32(bytes, 4, <f64>canvas.height);
        Buffer.writef32(bytes, 8, this.bias);
        Buffer.writef32(bytes, 12, debug);
        Buffer.writef32(bytes, 16, this.featureBits);
        this.showUniforms!.update(0, bytes);

        this.showAttachment.view = null;
        let pass = canvas.beginRenderPass(this.showPassDesc);
        pass.setPipeline(showPipeline);
        pass.setBindGroup(0, this.newestIsA ? this.showReadA! : this.showReadB!);
        pass.draw(3);
        pass.finish();

        // The canvas is sized in device pixels, the scene in layout points:
        // on a 2x or 3x screen the image must be drawn that much smaller, or
        // the surface lands at twice or three times where the strings are.
        renderer.save();
        renderer.transform(Mat2D.withScale(
            <f32>(this.width / <f64>canvas.width),
            <f32>(this.height / <f64>canvas.height)));
        renderer.drawImage(canvas.image, this.imageSampler, BlendMode.srcOver, 1);
        renderer.restore();
    }
}
