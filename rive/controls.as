// Discrete alternatives to drawing and dragging. Selection refers to the
// real strings, including ones drawn with a pointer, not a second list.
import { Strings, StringLine, Struck, PULL_LIMIT } from "./strings";
import { chordMidi, frequencyOf } from "./harmony";

export class Controls {
    selected: StringLine? = null;
    placement: i32 = 0;

    kept(strings: Strings): Array<StringLine> {
        let lines: Array<StringLine> = [];
        for (let i = 0; i < strings.lines.length; i++) {
            let line = strings.lines[i];
            if (!line.leaving) lines.push(line);
        }
        return lines;
    }

    current(strings: Strings): StringLine? {
        let selected = this.selected;
        if (selected != null && strings.keeps(selected)) return selected;
        let lines = this.kept(strings);
        this.selected = lines.length > 0 ? lines[lines.length - 1] : null;
        return this.selected;
    }

    create(strings: Strings, width: f64, height: f64, fraction: f64): StringLine {
        let length = Math.max(40, Math.min(width - 32, height * Math.min(Math.max(fraction, 0.2), 0.8)));
        let x = (width - length) / 2;
        let y = height * (0.22 + <f64>(this.placement++ % 8) * 0.055);
        let line = strings.add(x, y, x + length, y);
        this.selected = line;
        return line;
    }

    seed(strings: Strings, width: f64, height: f64, harmony: i32 = 0): void {
        if (this.kept(strings).length > 0) return;
        // Leave the bottom of even a small phone free for the harmony panel.
        let landscape = width >= 600 && height <= 500;
        let areaWidth = landscape ? width - 368 : width;
        let bottom = landscape ? height - 76 : Math.max(184, Math.min(height * 0.48, height - 340));
        let longest = Math.max(40, Math.min(areaWidth - 48, height * 0.68));
        for (let degree = 0; degree < 3; degree++) {
            let midi = chordMidi(harmony, degree);
            let length = longest * Math.pow(2, <f64>(chordMidi(harmony, 0) - midi) / 12);
            let x = (areaWidth - length) / 2;
            let y = 84 + (bottom - 84) * <f64>degree / 2;
            let line = strings.add(x, y, x + length, y);
            // Only this explicitly requested preset assigns chord pitches.
            line.frequency = frequencyOf(midi);
            this.selected = line;
        }
    }

    select(strings: Strings, direction: i32): void {
        let lines = this.kept(strings);
        if (lines.length == 0) {
            this.selected = null;
            return;
        }
        let selected = this.current(strings);
        let index = 0;
        for (let i = 0; i < lines.length; i++) {
            if (lines[i] == selected) index = i;
        }
        this.selected = lines[(index + direction + lines.length) % lines.length];
    }

    pluck(strings: Strings, strength: f64): Struck? {
        let line = this.current(strings);
        if (line == null) return null;
        let amount = Math.min(Math.max(strength, 0.1), 1);
        line.hold(0.5);
        line.fingerTarget = line.length * PULL_LIMIT * amount;
        line.letGo();
        let struck = new Struck();
        struck.frequency = line.frequency;
        struck.strength = amount;
        return struck;
    }
}
