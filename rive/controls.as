// Discrete alternatives to drawing and dragging. Selection refers to the
// real strings, including ones drawn with a pointer, not a second list.
import { Strings, StringLine, Struck, PULL_LIMIT } from "./strings";

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
