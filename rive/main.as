// 잔향: lines drawn across a dark surface become strings. Pulled aside and
// let go, a string sounds, and its swing spreads through the surface as
// ripples and ink.
import { Layout, Context } from "rive/host";
import { Renderer } from "rive/renderer";
import { PointerEvent } from "rive/events";
import { Audio, AudioHandle } from "rive/audio";
import { PropertyNumber, PropertyString } from "rive/data";
import { Color } from "rive/color";
import { Medium, MAX_STRINGS, STEP } from "./medium";
import { Strings, Struck, SAMPLES, RELEASED_TAP, RELEASED_STRING, RELEASED_PLUCK } from "./strings";
import { Inputs, Note, Pluck } from "./pluck";
import { Guide } from "./guide";
import { Controls } from "./controls";
import { harmonyId } from "./harmony";
import { Phrase } from "./phrase";

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
    strings: Strings = new Strings();
    guide: Guide = new Guide();
    controls: Controls = new Controls();
    phrase: Phrase = new Phrase();
    cursorProperty: PropertyString? = null;
    cancelProperty: PropertyNumber? = null;
    harmonyProperty: PropertyNumber? = null;
    previewProperty: PropertyNumber? = null;
    drawingProperty: PropertyNumber? = null;
    cancelSerial: f64 = 0;
    showSelection: bool = false;
    notesPlayed: i32 = 0;

    inputs: Inputs = new Inputs();
    note: Note = new Note();
    sound: AudioHandle? = null;
    soundStarts: i32 = 0;

    width: f64 = 0;
    height: f64 = 0;
    pending: f64 = 0;
    pointerIsDown: bool = false;
    pointerId: f64 = -1;
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
        this.guide.resize(width, height);
    }

    override advance(seconds: f64): bool {
        this.syncControls();
        this.strings.advance(seconds);
        this.guide.advance(seconds, this.strings);
        let wasPlaying = this.phrase.playing;
        let line = this.phrase.advance(seconds);
        if (wasPlaying && !this.phrase.playing) this.guide.left();
        if (line != null) {
            this.controls.selected = line;
            let struck = this.controls.pluck(this.strings, this.phrase.step % 3 == 1 ? 0.48 : 0.32);
            if (struck != null) this.soundNote(struck);
        }
        if (line != null || wasPlaying != this.phrase.playing) this.publishControls();
        this.publishPreview();
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
            this.cancelGesture();
        }
        let harmony = this.harmonyProperty;
        if (harmony != null && harmonyId(harmony.value) != this.strings.harmony) {
            this.beginControl();
            this.strings.tune(harmonyId(harmony.value));
            this.publishControls();
        }
    }

    private publishPreview(): void {
        let preview = this.previewProperty;
        let drawing = this.drawingProperty;
        if (preview != null) preview.value = this.strings.previewFrequency;
        if (drawing != null) drawing.value = this.strings.drawing ? 1 : 0;
    }

    private setCursor(value: string): void {
        let cursor = this.cursorProperty;
        if (cursor != null && cursor.value != value) cursor.value = value;
    }

    private cancelGesture(): void {
        let wasPlaying = this.phrase.playing;
        this.phrase.stop();
        this.pointerIsDown = false;
        this.pointerId = -1;
        this.strings.cancel();
        this.strings.unhover();
        this.guide.left();
        this.setCursor("crosshair");
        this.publishPreview();
        if (wasPlaying) this.publishControls();
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
        if (this.pointerIsDown) return;
        this.phrase.stop();
        this.showSelection = false;
        this.wakeSound();
        this.pointerIsDown = true;
        this.pointerId = event.id;
        this.strings.press(<f64>event.position.x, <f64>event.position.y);
        if (this.strings.held != null) this.controls.selected = this.strings.held;
        this.guide.pressed(this.strings);
        this.setCursor(this.strings.held != null ? "grabbing" : "crosshair");
        this.publishControls();
        event.hit();
    }

    override pointerMove(event: PointerEvent): void {
        this.syncControls();
        if (this.pointerIsDown && event.id != this.pointerId) return;
        if (this.pointerIsDown) {
            this.strings.drag(<f64>event.position.x, <f64>event.position.y);
            event.hit();
        } else {
            this.strings.hover(<f64>event.position.x, <f64>event.position.y);
            let hovered = this.strings.hovered;
            this.guide.hovering(hovered != null && hovered == this.guide.line);
            this.setCursor(hovered != null ? "grab" : "crosshair");
        }
    }

    override pointerUp(event: PointerEvent): void {
        // Escape/blur can arrive between the last frame and pointer-up.
        // Apply cancellation before committing a stroke or sounding a pluck.
        this.syncControls();
        if (!this.pointerIsDown || event.id != this.pointerId) {
            return;
        }
        this.pointerIsDown = false;
        this.pointerId = -1;
        let struck = this.strings.release(<f64>event.position.x, <f64>event.position.y);
        this.strings.unhover();
        this.guide.released(this.strings);
        if (this.strings.released == RELEASED_TAP) {
            this.medium.drop(this.strings.tapX, this.strings.tapY);
        }
        if (struck != null) {
            this.soundNote(struck);
        }
        if (this.strings.released == RELEASED_STRING) {
            this.controls.selected = this.strings.lines[this.strings.lines.length - 1];
        }
        this.publishControls();
        this.strings.hover(event.position.x, event.position.y);
        this.setCursor(this.strings.hovered != null ? "grab" : "crosshair");
        event.hit();
    }

    private soundNote(struck: Struck): void {
        this.note.frequency = <f32>struck.frequency;
        this.note.gain = <f32>(0.25 + 0.75 * struck.strength);
        this.inputs.notes.send(this.note);
        this.notesPlayed++;
    }

    // Stop a demonstration or an unfinished pointer gesture before a button
    // takes ownership. The guide sees the same successful releases.
    private beginControl(): void {
        this.cancelGesture();
        this.guide.controlStarted(this.strings);
        this.showSelection = true;
    }

    @input createString(): void {
        this.syncControls();
        this.beginControl();
        this.controls.create(this.strings, this.width, this.height, this.lengthFraction);
        this.strings.released = RELEASED_STRING;
        this.guide.released(this.strings);
        this.publishControls();
    }

    @input harmonyStrings(): void {
        this.syncControls();
        this.beginControl();
        this.controls.seed(this.strings, this.width, this.height);
        this.strings.released = RELEASED_STRING;
        this.guide.released(this.strings);
        this.publishControls();
    }

    @input playPhrase(): void {
        this.syncControls();
        let wasPlaying = this.phrase.playing;
        this.beginControl();
        if (!wasPlaying) {
            this.wakeSound();
            this.phrase.start(this.strings);
        }
        this.publishControls();
    }

    private selectString(direction: i32): void {
        this.beginControl();
        this.controls.select(this.strings, direction);
        this.guide.released(this.strings);
        this.publishControls();
    }

    @input previousString(): void { this.selectString(-1); }
    @input nextString(): void { this.selectString(1); }

    @input pluckString(): void {
        this.beginControl();
        let struck = this.controls.pluck(this.strings, this.pluckStrength);
        if (struck != null) {
            this.wakeSound();
            this.soundNote(struck);
            this.strings.released = RELEASED_PLUCK;
        }
        this.guide.released(this.strings);
        this.publishControls();
    }

    private publishControls(): void {
        let context = this.context;
        if (context == null) return;
        let vm = context.viewModel();
        if (vm == null) return;
        let selected = this.controls.current(this.strings);
        let lines = this.controls.kept(this.strings);
        let index = 0;
        for (let i = 0; i < lines.length; i++) {
            if (lines[i] == selected) index = i + 1;
        }
        let count = vm.getNumber("stringCount");
        let selection = vm.getNumber("selectedString");
        let frequency = vm.getNumber("frequency");
        let notes = vm.getNumber("notesPlayed");
        let demo = vm.getNumber("demoPlaying");
        if (count != null) count.value = <f64>lines.length;
        if (selection != null) selection.value = <f64>index;
        if (frequency != null) frequency.value = selected != null ? selected.frequency : 0;
        if (notes != null) notes.value = <f64>this.notesPlayed;
        if (demo != null) demo.value = this.phrase.playing ? 1 : 0;
    }

    override pointerExit(event: PointerEvent): void {
        if (!this.pointerIsDown || event.id == this.pointerId) this.cancelGesture();
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
                    PUSH * line.presence, REACH,
                    line.heldPoint >= 0 ? QUIET : 0, line.fullSpeed, this.offsets, this.previous);
                count++;
            }
            medium.step(count);
        }
        medium.show(renderer, this.debug);
        this.strings.draw(renderer);
        this.guide.draw(renderer, this.strings);
        let selected = this.controls.current(this.strings);
        if (this.showSelection && selected != null) {
            this.strings.drawDot(renderer, this.strings.pointOn(selected, 0.5), 4,
                Color.rgba(185, 223, 255, 150), Color.rgb(232, 242, 255));
        }
    }
}
