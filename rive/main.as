// 잔향: lines drawn across a dark surface become strings. Pulled aside and
// let go, a string sounds, and its swing spreads through the surface as
// ripples and ink.
import { Layout, Context } from "rive/host";
import { Renderer } from "rive/renderer";
import { PointerEvent } from "rive/events";
import { Audio, AudioHandle } from "rive/audio";
import { PropertyBoolean, PropertyNumber, PropertyString } from "rive/data";
import { Color } from "rive/color";
import { Medium, MAX_STRINGS, STEP } from "./medium";
import { Strings, Struck, SAMPLES, RELEASED_TAP, RELEASED_STRING, RELEASED_PLUCK } from "./strings";
import { Inputs, Note, Pluck } from "./pluck";
import { Guide } from "./guide";
import { Controls } from "./controls";
import { Bow } from "./bow";

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
    bow: Bow = new Bow();
    bowMode: bool = false;
    modeProperty: PropertyBoolean? = null;
    cursorProperty: PropertyString? = null;
    cancelProperty: PropertyNumber? = null;
    contactsProperty: PropertyNumber? = null;
    cancelSerial: f64 = 0;
    bowSoundTime: f64 = 0;
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
        this.bow.resize(width, height);
    }

    override advance(seconds: f64): bool {
        this.syncControls();
        this.bow.advance(seconds, this.strings);
        if (this.bow.sounding) this.guide.rung = true;
        if (this.bowMode && this.pointerIsDown) {
            this.bowSoundTime += seconds;
            if (this.bowSoundTime >= 1.0 / 60) {
                this.bowSoundTime = 0;
                this.sendBowNotes();
            }
        }
        let contacts = this.contactsProperty;
        if (contacts != null && contacts.value != this.bow.contacts) contacts.value = this.bow.contacts;
        this.strings.advance(seconds);
        if (!this.bowMode) this.guide.advance(seconds, this.strings);
        this.pending = Math.min(this.pending + seconds, MAX_CATCH_UP);

        return true;
    }

    private syncControls(): void {
        let context = this.context;
        if (context == null) return;
        if (this.modeProperty == null) {
            let model = context.viewModel();
            if (model == null) return;
            this.modeProperty = model.getBoolean("bowMode");
            this.cursorProperty = model.getString("cursor");
            this.cancelProperty = model.getNumber("cancelGesture");
            this.contactsProperty = model.getNumber("bowContacts");
        }
        let mode = this.modeProperty;
        let cancel = this.cancelProperty;
        if (mode != null && mode.value != this.bowMode) {
            this.cancelGesture();
            this.bowMode = mode.value;
            this.guide.controlStarted(this.strings);
            this.guide.left();
            this.setCursor(this.bowMode ? "grab" : "crosshair");
        }
        if (cancel != null && cancel.value != this.cancelSerial) {
            this.cancelSerial = cancel.value;
            this.cancelGesture();
        }
    }

    private setCursor(value: string): void {
        let cursor = this.cursorProperty;
        if (cursor != null && cursor.value != value) cursor.value = value;
    }

    private sendBowNotes(): void {
        let count = 0;
        let lines = this.strings.lines;
        for (let i = 0; i < lines.length; i++) {
            if (!lines[i].leaving && lines[i].bowStrength > 0) count++;
        }
        let balance = 1 / Math.sqrt(Math.max(1, count));
        let voice = 0;
        for (let i = 0; i < lines.length && voice < 12; i++) {
            let line = lines[i];
            if (line.leaving) continue;
            this.note.voice = voice++;
            this.note.frequency = <f32>line.frequency;
            this.note.gain = <f32>(line.bowStrength * balance);
            this.inputs.notes.send(this.note);
        }
        while (voice < 12) {
            this.note.voice = voice++;
            this.note.gain = 0;
            this.inputs.notes.send(this.note);
        }
    }

    private cancelGesture(): void {
        this.pointerIsDown = false;
        this.pointerId = -1;
        this.strings.cancel();
        this.strings.unhover();
        this.bow.cancel(this.strings);
        this.sendBowNotes();
        this.guide.left();
        this.setCursor(this.bowMode ? "grab" : "crosshair");
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
        this.showSelection = false;
        this.wakeSound();
        this.pointerIsDown = true;
        this.pointerId = event.id;
        if (this.bowMode) this.bow.press(event.position.x, event.position.y, this.strings);
        else this.strings.press(<f64>event.position.x, <f64>event.position.y);
        if (this.strings.held != null) this.controls.selected = this.strings.held;
        this.guide.pressed(this.strings);
        this.setCursor(this.bowMode || this.strings.held != null ? "grabbing" : "crosshair");
        event.hit();
    }

    override pointerMove(event: PointerEvent): void {
        this.syncControls();
        if (this.pointerIsDown && event.id != this.pointerId) return;
        if (this.bowMode) {
            this.bow.move(event.position.x, event.position.y, this.strings);
            event.hit();
            return;
        }
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
        if (!this.pointerIsDown || event.id != this.pointerId) {
            return;
        }
        this.pointerIsDown = false;
        this.pointerId = -1;
        if (this.bowMode) {
            this.bow.cancel(this.strings);
            this.sendBowNotes();
            this.bow.move(event.position.x, event.position.y, this.strings);
            this.guide.left();
            this.setCursor("grab");
            event.hit();
            return;
        }
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
        this.note.voice = -1;
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
        this.beginControl();
        this.controls.create(this.strings, this.width, this.height, this.lengthFraction);
        this.strings.released = RELEASED_STRING;
        this.guide.released(this.strings);
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
        if (count != null) count.value = <f64>lines.length;
        if (selection != null) selection.value = <f64>index;
        if (frequency != null) frequency.value = selected != null ? selected.frequency : 0;
        if (notes != null) notes.value = <f64>this.notesPlayed;
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
        if (this.bowMode) this.bow.draw(renderer, this.strings);
        else this.guide.draw(renderer, this.strings);
        let selected = this.controls.current(this.strings);
        if (this.showSelection && selected != null) {
            this.strings.drawDot(renderer, this.strings.pointOn(selected, 0.5), 4,
                Color.rgba(185, 223, 255, 150), Color.rgb(232, 242, 255));
        }
    }
}
