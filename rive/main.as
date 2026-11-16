// 잔향: lines drawn across a dark surface become strings. Pulled aside and
// let go, a string sounds, and its swing spreads through the surface as
// ripples and ink.
import { Layout, Context } from "rive/host";
import { Renderer } from "rive/renderer";
import { PointerEvent } from "rive/events";
import { Audio, AudioHandle } from "rive/audio";
import { Medium, MAX_STRINGS, STEP } from "./medium";
import { Strings, SAMPLES } from "./strings";
import { Inputs, Note, Pluck } from "./pluck";

// The most time one draw catches the surface up on. A frame can come late,
// and a headless capture advances many times before its single draw.
const MAX_CATCH_UP: f64 = 0.5;
// How hard a string at full swing pushes the surface each step.
const PUSH: f64 = 0.05;
// Points to either side of a string its push reaches.
const REACH: f64 = 12;
// Times the sound is started before a failing one is left silent.
const MAX_SOUND_STARTS: i32 = 3;

export class Main extends Layout {
    // 1 draws the markers that show which way up the scene arrives and what
    // the GPU offers. On while stage 1 is being checked in browsers.
    @input debug: f64 = 1;

    context: Context? = null;
    medium: Medium = new Medium();
    strings: Strings = new Strings();

    inputs: Inputs = new Inputs();
    note: Note = new Note();
    sound: AudioHandle? = null;
    soundStarts: i32 = 0;

    width: f64 = 0;
    height: f64 = 0;
    pending: f64 = 0;
    pointerIsDown: bool = false;
    // Scratch for one string's shape and motion, handed to the surface
    // each step.
    offsets: StaticArray<f32> = new StaticArray<f32>(SAMPLES);
    previous: StaticArray<f32> = new StaticArray<f32>(SAMPLES);

    override init(context: Context): bool {
        this.context = context;
        if (!this.medium.setup(context)) {
            return false;
        }
        return true;
    }

    override resize(width: f64, height: f64, scale: f64): void {
        this.width = width;
        this.height = height;
        this.strings.height = height;
        this.medium.resize(width, height, scale);
    }

    override advance(seconds: f64): bool {
        this.strings.advance(seconds);
        this.pending = Math.min(this.pending + seconds, MAX_CATCH_UP);

        return true;
    }

    // Starts the sound, or starts it again after it failed. It waits for a
    // press because a browser gives a page no sound before one, and gives
    // up after a few tries so a lasting fault is not retried for ever.
    private wakeSound(): void {
        let sound = this.sound;
        if (sound != null) {
            let failed = sound.failed;
            if (failed == null) {
                return;
            }
            let context = this.context;
            if (context != null) {
                context.log("janhyang: sound stopped: " + failed);
            }
            sound.release();
            this.sound = null;
        }
        if (this.soundStarts >= MAX_SOUND_STARTS) {
            return;
        }
        this.soundStarts++;
        this.sound = Audio.start(() => new Pluck(), this.inputs);
        let context = this.context;
        if (context != null) {
            context.log("janhyang: sound started, rate " + Audio.processorSampleRate().toString());
        }
    }

    override pointerDown(event: PointerEvent): void {
        this.wakeSound();
        this.pointerIsDown = true;
        this.strings.press(<f64>event.position.x, <f64>event.position.y);
        event.hit();
    }

    override pointerMove(event: PointerEvent): void {
        if (this.pointerIsDown) {
            this.strings.drag(<f64>event.position.x, <f64>event.position.y);
            event.hit();
        }
    }

    override pointerUp(event: PointerEvent): void {
        if (!this.pointerIsDown) {
            return;
        }
        this.pointerIsDown = false;
        let struck = this.strings.release(<f64>event.position.x, <f64>event.position.y);
        if (struck != null) {
            this.note.frequency = <f32>struck.frequency;
            this.note.gain = <f32>(0.25 + 0.75 * struck.strength);
            this.inputs.notes.send(this.note);
        }
        event.hit();
    }

    override pointerExit(event: PointerEvent): void {
        this.pointerIsDown = false;
        this.strings.cancel();
    }

    override draw(renderer: Renderer): void {
        let medium = this.medium;
        if (!medium.ready) {
            return;
        }
        let lines = this.strings.lines;
        let steps = <i32>Math.floor(this.pending / STEP);
        this.pending -= steps * STEP;
        for (let i = 0; i < steps; i++) {
            // The strings and the surface move on together, a step at a time,
            // so the water answers each string where it is at that moment.
            this.strings.step();
            let count = 0;
            for (let s = 0; s < lines.length && count < MAX_STRINGS; s++) {
                let line = lines[s];
                if (!line.awake) {
                    continue;
                }
                line.sample(this.offsets, this.previous);
                medium.setString(count, line.ax, line.ay, line.bx, line.by,
                    PUSH * line.presence, REACH, this.offsets, this.previous);
                count++;
            }
            medium.step(count);
        }
        medium.show(renderer, this.debug);
        this.strings.draw(renderer);
    }
}
