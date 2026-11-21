import { Renderer } from "rive/renderer";
import { Color } from "rive/color";
import { Strings, StringLine, Struck, RELEASED_TAP, RELEASED_STRING, RELEASED_PLUCK } from "./strings";
import { Controls } from "./controls";
import { Guide } from "./guide";
import { Phrase } from "./phrase";

export class Release {
    accepted: bool = false;
    note: Struck? = null;
    tapped: bool = false;
    x: f64 = 0;
    y: f64 = 0;
}

// Owns the order of an interaction, independent of the host's GPU and audio.
// Strings and Guide also expose the visual state consumed by drawing/tests.
export class Performance {
    strings: Strings = new Strings();
    guide: Guide = new Guide();
    private controls: Controls = new Controls();
    private phrase: Phrase = new Phrase();
    private pointerId: f64 = -1;
    private pointerDown: bool = false;
    private width: f64 = 0;
    private height: f64 = 0;
    private showSelection: bool = false;
    private releaseResult: Release = new Release();
    cursor: string = "crosshair";
    notesPlayed: i32 = 0;
    revision: i32 = 0;

    get selected(): StringLine? { return this.controls.current(this.strings); }
    get count(): i32 { return this.controls.kept(this.strings).length; }
    get selectedIndex(): i32 {
        let selected = this.selected;
        let lines = this.controls.kept(this.strings);
        for (let i = 0; i < lines.length; i++) if (lines[i] == selected) return i + 1;
        return 0;
    }
    get frequency(): f64 {
        let selected = this.selected;
        return selected != null ? selected.frequency : 0;
    }
    get demoPlaying(): bool { return this.phrase.playing; }

    resize(width: f64, height: f64): void {
        this.width = width;
        this.height = height;
        this.strings.height = height;
        this.guide.resize(width, height);
    }

    advance(seconds: f64): Struck? {
        this.strings.advance(seconds);
        this.guide.advance(seconds, this.strings);
        let wasPlaying = this.phrase.playing;
        let line = this.phrase.advance(seconds);
        if (wasPlaying && !this.phrase.playing) this.guide.left();
        let note: Struck? = null;
        if (line != null) {
            this.controls.selected = line;
            note = this.record(this.controls.pluck(this.strings, this.phrase.step % 3 == 1 ? 0.48 : 0.32));
        }
        if (line != null || wasPlaying != this.phrase.playing) this.revision++;
        return note;
    }

    press(id: f64, x: f64, y: f64): bool {
        if (this.pointerDown) return false;
        this.phrase.stop();
        this.showSelection = false;
        this.pointerDown = true;
        this.pointerId = id;
        this.strings.press(x, y);
        if (this.strings.held != null) this.controls.selected = this.strings.held;
        this.guide.pressed(this.strings);
        this.cursor = this.strings.held != null ? "grabbing" : "crosshair";
        this.revision++;
        return true;
    }

    move(id: f64, x: f64, y: f64): bool {
        if (this.pointerDown && id != this.pointerId) return false;
        if (this.pointerDown) {
            this.strings.drag(x, y);
            return true;
        }
        this.strings.hover(x, y);
        let hovered = this.strings.hovered;
        this.guide.hovering(hovered != null && hovered == this.guide.line);
        this.cursor = hovered != null ? "grab" : "crosshair";
        return false;
    }

    // The result is borrowed until the next release; no host state is needed.
    release(id: f64, x: f64, y: f64): Release {
        let result = this.releaseResult;
        result.accepted = false;
        result.note = null;
        result.tapped = false;
        if (!this.pointerDown || id != this.pointerId) return result;
        this.pointerDown = false;
        this.pointerId = -1;
        result.accepted = true;
        result.note = this.record(this.strings.release(x, y));
        this.strings.unhover();
        this.guide.released(this.strings);
        result.tapped = this.strings.released == RELEASED_TAP;
        result.x = this.strings.tapX;
        result.y = this.strings.tapY;
        if (this.strings.released == RELEASED_STRING) {
            this.controls.selected = this.strings.lines[this.strings.lines.length - 1];
        }
        this.strings.hover(x, y);
        this.cursor = this.strings.hovered != null ? "grab" : "crosshair";
        this.revision++;
        return result;
    }

    cancel(): void {
        this.phrase.stop();
        this.pointerDown = false;
        this.pointerId = -1;
        this.strings.cancel();
        this.strings.unhover();
        this.guide.left();
        this.cursor = "crosshair";
        this.revision++;
    }

    leave(id: f64): void {
        if (!this.pointerDown || id == this.pointerId) this.cancel();
    }

    private beginControl(): void {
        this.cancel();
        this.guide.controlStarted(this.strings);
        this.showSelection = true;
    }

    createString(fraction: f64): void {
        this.beginControl();
        this.controls.create(this.strings, this.width, this.height, fraction);
        this.strings.released = RELEASED_STRING;
        this.guide.released(this.strings);
    }

    harmonyStrings(harmony: i32): void {
        this.beginControl();
        let before = this.count;
        this.controls.seed(this.strings, this.width, this.height, harmony);
        if (this.count > before) this.strings.released = RELEASED_STRING;
        this.guide.released(this.strings);
    }

    playPhrase(): bool {
        let wasPlaying = this.phrase.playing;
        this.beginControl();
        if (!wasPlaying) this.phrase.start(this.strings);
        return this.phrase.playing;
    }

    selectString(direction: i32): void {
        this.beginControl();
        this.controls.select(this.strings, direction);
        this.guide.released(this.strings);
    }

    pluckString(strength: f64): Struck? {
        this.beginControl();
        let note = this.record(this.controls.pluck(this.strings, strength));
        if (note != null) this.strings.released = RELEASED_PLUCK;
        this.guide.released(this.strings);
        return note;
    }

    private record(note: Struck?): Struck? {
        if (note != null) this.notesPlayed++;
        return note;
    }

    draw(renderer: Renderer): void {
        this.strings.draw(renderer);
        this.guide.draw(renderer, this.strings);
        let selected = this.selected;
        if (this.showSelection && selected != null) {
            this.strings.drawDot(renderer, this.strings.pointOn(selected, 0.5), 4,
                Color.rgba(185, 223, 255, 150), Color.rgb(232, 242, 255));
        }
    }
}
