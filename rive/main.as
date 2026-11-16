// Stage 1 check: the medium on its own. The whole scene is one shader
// simulation that carries on from frame to frame, stirred by the pointer.
import { Layout, Context } from "rive/host";
import { Renderer } from "rive/renderer";
import { PointerEvent } from "rive/events";
import { Buffer } from "rive/buffer";
import { BlendMode } from "rive/paint";
import { ImageSampler, ImageWrap, ImageFilter } from "rive/image";
import {
    GPUBindGroup, GPUBindGroupSampler, GPUBindGroupTexture, GPUBindGroupUBO,
    GPUBuffer, GPUCanvas, GPUColorAttachment, GPUColorTargetDesc, GPUPassDesc,
    GPUPipeline, GPUPipelineDesc, GPUSampler, GPUShaderModule, GPUTexture,
    GPUTextureDesc, GPUTextureView,
} from "rive/gpu";
import {
    BufferUsage, Filter, LoadOp, StoreOp, TextureFormat, WrapMode,
} from "rive/gpu_enums";

// The simulation runs at a fixed height and step, whatever the screen: a
// browser can hand over a frame of nearly a second or run at 120 Hz, and
// the wave must behave the same either way.
const SIM_HEIGHT: u32 = 360;
const STEP: f64 = 1.0 / 120.0;
// The most time one draw catches up on. A frame can come late, and a
// headless capture advances many times before its single draw.
const MAX_CATCH_UP: f64 = 0.5;
const UNIFORM_BYTES: u32 = 32;

export class Main extends Layout {
    // 1 draws the orientation and feature markers.
    @input debug: f64 = 1;

    context: Context? = null;
    canvas: GPUCanvas? = null;
    simShader: GPUShaderModule? = null;
    showShader: GPUShaderModule? = null;
    simPipeline: GPUPipeline? = null;
    showPipeline: GPUPipeline? = null;

    // Two copies of the state: each step reads one and writes the other.
    stateA: GPUTexture? = null;
    stateB: GPUTexture? = null;
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
    simBytes: ArrayBuffer = Buffer.create(UNIFORM_BYTES);
    showBytes: ArrayBuffer = Buffer.create(UNIFORM_BYTES);
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
    scale: f64 = 1;
    simWidth: u32 = 0;

    pending: f64 = 0;

    // Pointer in scene space, 0 to 1 with y down.
    pointerX: f64 = 0.5;
    pointerY: f64 = 0.5;
    previousX: f64 = 0.5;
    previousY: f64 = 0.5;
    pointerDownNow: bool = false;
    // Strength carried into the next steps, so a quick tap still lands.
    push: f64 = 0;

    override init(context: Context): bool {
        this.context = context;
        // init runs twice; everything below is made once.
        if (this.simShader != null) {
            return true;
        }
        let simShader = context.shader("sim");
        let showShader = context.shader("show");
        if (simShader == null || showShader == null) {
            context.log("janhyang: shader missing");
            return false;
        }
        this.simShader = simShader;
        this.showShader = showShader;

        let features = context.features();
        if (features.colorBufferHalfFloat) {
            this.stateFormat = TextureFormat.rgba16float;
            this.bias = 0;
            this.featureBits = features.colorBufferFloat ? 2 : 1;
        }
        context.log("janhyang: features known=" + features.known.toString()
            + " halfFloat=" + features.colorBufferHalfFloat.toString()
            + " float=" + features.colorBufferFloat.toString()
            + " maxTexture=" + features.maxTextureSize2D.toString());

        this.canvas = context.gpuCanvas(0, 0);
        this.stateSampler = new GPUSampler(
            Filter.linear, Filter.linear, Filter.nearest,
            WrapMode.clampToEdge, WrapMode.clampToEdge);
        this.simUniforms = new GPUBuffer(BufferUsage.uniform, UNIFORM_BYTES);
        this.showUniforms = new GPUBuffer(BufferUsage.uniform, UNIFORM_BYTES);

        this.simAttachment.loadOp = LoadOp.clear;
        this.simAttachment.storeOp = StoreOp.store;
        this.simPassDesc.color = [this.simAttachment];
        this.showAttachment.loadOp = LoadOp.clear;
        this.showAttachment.storeOp = StoreOp.store;
        this.showPassDesc.color = [this.showAttachment];
        return true;
    }

    override resize(width: f64, height: f64, scale: f64): void {
        this.width = width;
        this.height = height;
        this.scale = scale;
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
        let stateA = new GPUTexture(desc);
        let stateB = new GPUTexture(desc);
        let viewA = stateA.view();
        let viewB = stateB.view();
        this.stateA = stateA;
        this.stateB = stateB;
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

    override advance(seconds: f64): bool {
        this.pending = Math.min(this.pending + seconds, MAX_CATCH_UP);
        return true;
    }

    private setPointer(event: PointerEvent): void {
        if (this.width <= 0 || this.height <= 0) {
            return;
        }
        this.pointerX = <f64>event.position.x / this.width;
        this.pointerY = <f64>event.position.y / this.height;
    }

    override pointerDown(event: PointerEvent): void {
        this.setPointer(event);
        this.previousX = this.pointerX;
        this.previousY = this.pointerY;
        this.pointerDownNow = true;
        this.push = 1;
        event.hit();
    }

    override pointerMove(event: PointerEvent): void {
        if (this.pointerDownNow) {
            this.setPointer(event);
            this.push = 1;
            event.hit();
        }
    }

    override pointerUp(event: PointerEvent): void {
        if (this.pointerDownNow) {
            this.setPointer(event);
            this.pointerDownNow = false;
            event.hit();
        }
    }

    override pointerExit(event: PointerEvent): void {
        this.pointerDownNow = false;
    }

    private writeSimUniforms(strength: f64): void {
        let bytes = this.simBytes;
        Buffer.writef32(bytes, 0, this.pointerX);
        Buffer.writef32(bytes, 4, this.pointerY);
        Buffer.writef32(bytes, 8, this.previousX);
        Buffer.writef32(bytes, 12, this.previousY);
        Buffer.writef32(bytes, 16, strength);
        Buffer.writef32(bytes, 20, 0.018);
        Buffer.writef32(bytes, 24, this.bias);
        Buffer.writef32(bytes, 28, this.height > 0 ? this.width / this.height : 1);
        this.simUniforms!.update(0, bytes);
    }

    override draw(renderer: Renderer): void {
        let canvas = this.canvas;
        let simPipeline = this.simPipeline;
        let showPipeline = this.showPipeline;
        let viewA = this.viewA;
        let viewB = this.viewB;
        if (canvas == null || simPipeline == null || showPipeline == null
            || viewA == null || viewB == null || canvas.width == 0) {
            return;
        }

        // A new state starts level: height and velocity at rest, no ink.
        if (!this.cleared) {
            let rest = <f32>this.bias;
            let attachment = this.simAttachment;
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

        let steps = <i32>Math.floor(this.pending / STEP);
        this.pending -= steps * STEP;
        for (let i = 0; i < steps; i++) {
            // Only the first step of a frame carries the stroke.
            this.writeSimUniforms(i == 0 ? this.push * 0.12 : 0);
            let attachment = this.simAttachment;
            attachment.loadOp = LoadOp.dontCare;
            attachment.view = this.newestIsA ? viewB : viewA;
            let pass = canvas.beginRenderPass(this.simPassDesc);
            pass.setViewport(0, 0, <f32>this.simWidth, <f32>SIM_HEIGHT);
            pass.setPipeline(simPipeline);
            pass.setBindGroup(0, this.newestIsA ? this.simReadA! : this.simReadB!);
            pass.draw(3);
            pass.finish();
            this.newestIsA = !this.newestIsA;
            if (i == 0) {
                this.previousX = this.pointerX;
                this.previousY = this.pointerY;
                this.push = 0;
            }
        }

        let bytes = this.showBytes;
        Buffer.writef32(bytes, 0, <f64>canvas.width);
        Buffer.writef32(bytes, 4, <f64>canvas.height);
        Buffer.writef32(bytes, 8, this.bias);
        Buffer.writef32(bytes, 12, this.debug);
        Buffer.writef32(bytes, 16, this.featureBits);
        this.showUniforms!.update(0, bytes);

        this.showAttachment.view = null;
        let pass = canvas.beginRenderPass(this.showPassDesc);
        pass.setPipeline(showPipeline);
        pass.setBindGroup(0, this.newestIsA ? this.showReadA! : this.showReadB!);
        pass.draw(3);
        pass.finish();

        renderer.drawImage(canvas.image, this.imageSampler, BlendMode.srcOver, 1);
    }
}
