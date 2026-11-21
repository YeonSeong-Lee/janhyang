// 잔향: lines drawn across a dark surface become strings. Pulled aside and
// let go, a string sounds, and its swing spreads through the surface as
// ripples and ink.
import { Layout, Context } from "rive/host";
import { Renderer } from "rive/renderer";
import { PointerEvent } from "rive/events";
import { Audio, AudioHandle } from "rive/audio";
import { PropertyNumber, PropertyString } from "rive/data";
import { Medium, MAX_STRINGS, STEP } from "./medium";
import { Struck, SAMPLES } from "./strings";
import { Inputs, Note, Pluck } from "./pluck";
import { Performance } from "./performance";
import { harmonyId } from "./harmony";

// The most time one draw catches the surface up on. A frame can come late,
// and a headless capture advances many times before its single draw.
const MAX_CATCH_UP: f64 = 0.5;
// How hard a string at full swing pushes the surface each step.
const PUSH: f64 = 0.045;
// Points to either side of a string its push reaches.
const REACH: f64 = 12;
// Points a string held by a finger may move in a step and leave the water
// still: a hand easing a string aside moves it about a point a step, and
// slides it through the water. Let go, every motion stirs it.
const QUIET: f64 = 2;
// Times the sound is started before a failing one is left silent.
const MAX_SOUND_STARTS: i32 = 3;

export class Main extends Layout {
    // 1 draws the markers that show which way up the scene arrives and what
    // the GPU offers. Off by default; set to 1 when checking a new backend.
    @input debug: f64 = 0;
    @input lengthFraction: f64 = 0.5;
    @input pluckStrength: f64 = 0.5;

    context: Context? = null;
    medium: Medium = new Medium();
    performance: Performance = new Performance();
    publishedRevision: i32 = -1;
    cursorProperty: PropertyString? = null;
    cancelProperty: PropertyNumber? = null;
    harmonyProperty: PropertyNumber? = null;
    starterHarmony: i32 = 0;
    previewProperty: PropertyNumber? = null;
    drawingProperty: PropertyNumber? = null;
    cancelSerial: f64 = 0;

    inputs: Inputs = new Inputs();
    note: Note = new Note();
    sound: AudioHandle? = null;
    soundStarts: i32 = 0;

    pending: f64 = 0;
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
        this.performance.resize(width, height);
        this.medium.resize(width, height, scale);
    }

    override advance(seconds: f64): bool {
        this.syncControls();
        let note = this.performance.advance(seconds);
        if (note != null) this.soundNote(note);
        this.publish();
        this.pending = Math.min(this.pending + seconds, MAX_CATCH_UP);
        return true;
    }

    private syncControls(): void {
        let context = this.context;
        if (context == null) return;
        if (this.cursorProperty == null) {
            let model = context.viewModel();
            if (model == null) return;
            this.cursorProperty = model.getString("cursor");
            this.cancelProperty = model.getNumber("cancelGesture");
            this.harmonyProperty = model.getNumber("harmony");
            this.previewProperty = model.getNumber("previewFrequency");
            this.drawingProperty = model.getNumber("drawing");
        }
        let cancel = this.cancelProperty;
        if (cancel != null && cancel.value != this.cancelSerial) {
            this.cancelSerial = cancel.value;
            this.performance.cancel();
        }
        let harmony = this.harmonyProperty;
        if (harmony != null) this.starterHarmony = harmonyId(harmony.value);
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
    }

    override pointerDown(event: PointerEvent): void {
        this.syncControls();
        if (this.performance.press(event.id, event.position.x, event.position.y)) {
            this.wakeSound();
            event.hit();
        }
        this.publish();
    }

    override pointerMove(event: PointerEvent): void {
        this.syncControls();
        if (this.performance.move(event.id, event.position.x, event.position.y)) event.hit();
        this.publish();
    }

    override pointerUp(event: PointerEvent): void {
        // Apply pending cancellation before a release can create a string/note.
        this.syncControls();
        let result = this.performance.release(event.id, event.position.x, event.position.y);
        if (result.accepted) {
            if (result.tapped) this.medium.drop(result.x, result.y);
            let note = result.note;
            if (note != null) this.soundNote(note);
            event.hit();
        }
        this.publish();
    }

    private soundNote(struck: Struck): void {
        this.note.frequency = <f32>struck.frequency;
        this.note.gain = <f32>(0.25 + 0.75 * struck.strength);
        this.inputs.notes.send(this.note);
    }

    @input createString(): void {
        this.syncControls();
        this.performance.createString(this.lengthFraction);
        this.publish();
    }

    @input harmonyStrings(): void {
        this.syncControls();
        this.performance.harmonyStrings(this.starterHarmony);
        this.publish();
    }

    @input playPhrase(): void {
        this.syncControls();
        if (this.performance.playPhrase()) this.wakeSound();
        this.publish();
    }

    private selectString(direction: i32): void {
        this.syncControls();
        this.performance.selectString(direction);
        this.publish();
    }

    @input previousString(): void { this.selectString(-1); }
    @input nextString(): void { this.selectString(1); }

    @input pluckString(): void {
        this.syncControls();
        let note = this.performance.pluckString(this.pluckStrength);
        if (note != null) {
            this.wakeSound();
            this.soundNote(note);
        }
        this.publish();
    }

    private publish(): void {
        let performance = this.performance;
        let preview = this.previewProperty;
        let drawing = this.drawingProperty;
        let cursor = this.cursorProperty;
        if (preview != null) preview.value = performance.strings.previewFrequency;
        if (drawing != null) drawing.value = performance.strings.drawing ? 1 : 0;
        if (cursor != null && cursor.value != performance.cursor) cursor.value = performance.cursor;
        if (this.publishedRevision == performance.revision) return;
        let context = this.context;
        if (context == null) return;
        let vm = context.viewModel();
        if (vm == null) return;
        this.publishedRevision = performance.revision;
        let count = vm.getNumber("stringCount");
        let selection = vm.getNumber("selectedString");
        let frequency = vm.getNumber("frequency");
        let notes = vm.getNumber("notesPlayed");
        let demo = vm.getNumber("demoPlaying");
        if (count != null) count.value = <f64>performance.count;
        if (selection != null) selection.value = <f64>performance.selectedIndex;
        if (frequency != null) frequency.value = performance.frequency;
        if (notes != null) notes.value = <f64>performance.notesPlayed;
        if (demo != null) demo.value = performance.demoPlaying ? 1 : 0;
    }

    override pointerExit(event: PointerEvent): void {
        this.performance.leave(event.id);
        this.publish();
    }

    override draw(renderer: Renderer): void {
        let medium = this.medium;
        if (!medium.ready) {
            return;
        }
        let lines = this.performance.strings.lines;
        let steps = <i32>Math.floor(this.pending / STEP);
        this.pending -= steps * STEP;
        for (let i = 0; i < steps; i++) {
            // The strings and the surface move on together, a step at a time,
            // so the water answers each string where it is at that moment.
            this.performance.strings.step();
            let count = 0;
            for (let s = 0; s < lines.length && count < MAX_STRINGS; s++) {
                let line = lines[s];
                if (!line.awake) {
                    continue;
                }
                line.sample(this.offsets, this.previous);
                medium.setString(count, line.ax, line.ay, line.bx, line.by,
                    PUSH * line.presence, REACH,
                    line.heldPoint >= 0 ? QUIET : 0, line.fullSpeed, this.offsets, this.previous);
                count++;
            }
            medium.step(count);
        }
        medium.show(renderer, this.debug);
        this.performance.draw(renderer);
    }
}
