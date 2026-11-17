import { Strings, StringLine } from "./strings";

const PATTERN: StaticArray<i32> = [0, 1, 2, 1, 0, 2, 1, 2, 0];

// Runs on the scene clock, so no browser timers can keep playing after pause.
export class Phrase {
    lines: Array<StringLine> = [];
    playing: bool = false;
    step: i32 = 0;
    wait: f64 = 0;

    start(strings: Strings): void {
        this.lines = [];
        for (let i = 0; i < strings.lines.length; i++) {
            let line = strings.lines[i];
            if (line.leaving) continue;
            let index = 0;
            while (index < this.lines.length && this.lines[index].frequency < line.frequency) index++;
            this.lines.push(line);
            for (let j = this.lines.length - 1; j > index; j--) this.lines[j] = this.lines[j - 1];
            this.lines[index] = line;
        }
        this.step = 0;
        this.wait = 0;
        this.playing = this.lines.length > 0;
    }

    stop(): void {
        this.playing = false;
        this.lines = [];
    }

    advance(seconds: f64): StringLine? {
        if (!this.playing) return null;
        this.wait -= Math.max(0, seconds);
        if (this.wait > 0) return null;
        if (this.step >= PATTERN.length) {
            this.stop();
            return null;
        }
        let degree = PATTERN[this.step++];
        let index = <i32>Math.round(<f64>degree / 2 * <f64>(this.lines.length - 1));
        // A late frame extends the phrase instead of bursting overdue notes.
        this.wait = this.step == PATTERN.length ? 0.9 : 0.48;
        let line = this.lines[index];
        return line.leaving ? null : line;
    }
}
