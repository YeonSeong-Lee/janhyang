// The strings: lines the player draws across the surface, pulled aside and
// let go to ring.
import { Color } from "rive/color";
import { Paint, PaintStyle, StrokeCap, StrokeJoin } from "rive/paint";
import { Path } from "rive/path";
import { Renderer } from "rive/renderer";
import { Vector } from "rive/vector";

/// The most strings kept; drawing one more lets the oldest go.
export const MAX_KEPT: i32 = 12;

// Points from a string within which a press takes hold of it.
const GRAB_REACH: f64 = 18;
// A line shorter than this, in points, is a tap and makes no string.
const SHORTEST: f64 = 40;
// The furthest a string can be pulled aside, as a fraction of its length.
const PULL_LIMIT: f64 = 0.22;
// Seconds a string let go takes to fade away.
const LET_GO: f64 = 0.9;
// Overtones the swing of a string is built from.
const MODES: i32 = 5;
// Straight pieces a string is drawn with.
const PIECES: i32 = 40;

// The scale the strings are tuned to: A minor pentatonic, in semitones
// above A.
const SCALE: StaticArray<i32> = [0, 3, 5, 7, 10];

/// The pitch in Hz a string of `length` sounds, in a scene `height` tall.
/// Twice the length is an octave lower, and the result is moved to the
/// nearest note of the scale so that any set of strings sounds well together.
export function pitchOf(length: f64, height: f64): f64 {
    let relative = Math.max(length, 1) / Math.max(height, 1);
    let free = 12 * Math.log2(1 / relative) + 12;
    let nearest: f64 = 0;
    let closest: f64 = Infinity;
    for (let octave = -2; octave <= 4; octave++) {
        for (let i = 0; i < SCALE.length; i++) {
            let step = <f64>(octave * 12 + SCALE[i]);
            let gap = Math.abs(step - free);
            if (gap < closest) {
                closest = gap;
                nearest = step;
            }
        }
    }
    let frequency = 110 * Math.pow(2, nearest / 12);
    return Math.min(Math.max(frequency, 65), 1320);
}

export class StringLine {
    ax: f64 = 0;
    ay: f64 = 0;
    bx: f64 = 0;
    by: f64 = 0;
    length: f64 = 1;
    /// Pitch in Hz it sounds.
    frequency: f64 = 220;
    /// Swings a second it is seen to make, far slower than it sounds.
    rate: f64 = 8;

    /// How far its plucked point stood from rest when let go, in points,
    /// signed to one side.
    amplitude: f64 = 0;
    /// Where along it, 0 to 1, it was plucked.
    pluckedAt: f64 = 0.5;
    /// Seconds since it was let go.
    age: f64 = 0;
    ringing: bool = false;

    /// 1 while kept, falling to 0 once it is let go for good.
    presence: f64 = 1;
    leaving: bool = false;

    path: Path = new Path();

    constructor(ax: f64, ay: f64, bx: f64, by: f64, height: f64) {
        this.ax = ax;
        this.ay = ay;
        this.bx = bx;
        this.by = by;
        let dx = bx - ax;
        let dy = by - ay;
        this.length = Math.max(Math.sqrt(dx * dx + dy * dy), 1);
        this.frequency = pitchOf(this.length, height);
        this.rate = 5 + 2.4 * Math.log2(this.frequency / 65);
    }

    // How much the swing has died down `seconds` after the pluck.
    private fade(seconds: f64): f64 {
        return Math.exp(-seconds * (0.5 + this.rate * 0.05));
    }

    /// How far the string stands from rest at `along`, 0 to 1, in points to
    /// one side: the shape a string plucked at `pluckedAt` rings with, its
    /// overtones each swinging at their own rate and dying sooner the higher
    /// they are.
    swingAt(along: f64): f64 {
        if (!this.ringing) {
            return 0;
        }
        let total: f64 = 0;
        for (let n = 1; n <= MODES; n++) {
            let weight = Math.sin(n * Math.PI * this.pluckedAt) / <f64>(n * n);
            total += weight * Math.sin(n * Math.PI * along)
                * Math.cos(2 * Math.PI * n * this.rate * this.age)
                * Math.exp(-this.age * 0.4 * (n - 1));
        }
        return this.amplitude * this.fade(this.age) * total * 1.1;
    }

    /// How hard the string pushes the surface under it, `ahead` seconds
    /// from now: the speed of its main swing, as a fraction of its limit.
    pushAt(ahead: f64): f64 {
        if (!this.ringing) {
            return 0;
        }
        let at = Math.max(this.age + ahead, 0);
        let strength = this.amplitude / (this.length * PULL_LIMIT);
        return -strength * this.fade(at) * Math.sin(2 * Math.PI * this.rate * at) * this.presence;
    }

    /// True while the swing is still large enough to matter.
    get lively(): bool {
        return this.ringing && Math.abs(this.amplitude) * this.fade(this.age) > 0.05;
    }
}

/// What letting go of a string asks the sound for.
export class Struck {
    frequency: f64 = 0;
    /// 0 to 1.
    strength: f64 = 0;
}

export class Strings {
    lines: Array<StringLine> = [];
    height: f64 = 1;

    // A line being drawn.
    drawing: bool = false;
    startX: f64 = 0;
    startY: f64 = 0;
    endX: f64 = 0;
    endY: f64 = 0;
    draft: Path = new Path();

    // A string being held aside.
    held: StringLine? = null;
    heldAt: f64 = 0.5;
    heldOffset: f64 = 0;

    struck: Struck = new Struck();
    paint: Paint = new Paint();

    constructor() {
        this.paint.style = PaintStyle.stroke;
        this.paint.cap = StrokeCap.round;
        this.paint.join = StrokeJoin.round;
    }

    // Takes hold of the nearest string within reach of the point, if any.
    private take(x: f64, y: f64): bool {
        let best: StringLine? = null;
        let bestAlong: f64 = 0;
        let bestDistance: f64 = GRAB_REACH;
        for (let i = 0; i < this.lines.length; i++) {
            let line = this.lines[i];
            if (line.leaving) {
                continue;
            }
            let dx = line.bx - line.ax;
            let dy = line.by - line.ay;
            let along = ((x - line.ax) * dx + (y - line.ay) * dy) / (line.length * line.length);
            along = Math.min(Math.max(along, 0.06), 0.94);
            let px = line.ax + dx * along;
            let py = line.ay + dy * along;
            let distance = Math.sqrt((x - px) * (x - px) + (y - py) * (y - py));
            if (distance < bestDistance) {
                bestDistance = distance;
                best = line;
                bestAlong = along;
            }
        }
        if (best == null) {
            return false;
        }
        best.ringing = false;
        this.held = best;
        this.heldAt = bestAlong;
        this.heldOffset = 0;
        return true;
    }

    // Moves the held string's plucked point to follow the pointer, to one
    // side of the string and no further than it can stretch.
    private pull(x: f64, y: f64): void {
        let line = this.held;
        if (line == null) {
            return;
        }
        let dx = (line.bx - line.ax) / line.length;
        let dy = (line.by - line.ay) / line.length;
        let px = line.ax + (line.bx - line.ax) * this.heldAt;
        let py = line.ay + (line.by - line.ay) * this.heldAt;
        let offset = (x - px) * -dy + (y - py) * dx;
        let limit = line.length * PULL_LIMIT;
        this.heldOffset = Math.min(Math.max(offset, -limit), limit);
    }

    /// A press at the point: takes hold of a string there, or starts a line.
    press(x: f64, y: f64): void {
        if (this.take(x, y)) {
            return;
        }
        this.drawing = true;
        this.startX = x;
        this.startY = y;
        this.endX = x;
        this.endY = y;
    }

    /// The pointer moved while down.
    drag(x: f64, y: f64): void {
        if (this.held != null) {
            this.pull(x, y);
        } else if (this.drawing) {
            this.endX = x;
            this.endY = y;
        }
    }

    /// The pointer came up. Returns what to sound when a string was let
    /// go, or null when nothing rang.
    release(x: f64, y: f64): Struck? {
        let line = this.held;
        if (line != null) {
            this.pull(x, y);
            this.held = null;
            let limit = line.length * PULL_LIMIT;
            let strength = Math.abs(this.heldOffset) / limit;
            if (strength < 0.03) {
                return null;
            }
            line.amplitude = this.heldOffset;
            line.pluckedAt = this.heldAt;
            line.age = 0;
            line.ringing = true;
            this.struck.frequency = line.frequency;
            this.struck.strength = strength;
            return this.struck;
        }
        if (this.drawing) {
            this.drawing = false;
            this.endX = x;
            this.endY = y;
            let dx = this.endX - this.startX;
            let dy = this.endY - this.startY;
            if (Math.sqrt(dx * dx + dy * dy) >= SHORTEST) {
                this.add(this.startX, this.startY, this.endX, this.endY);
            }
        }
        return null;
    }

    /// The pointer left: whatever was in hand is dropped without a sound.
    cancel(): void {
        this.drawing = false;
        this.held = null;
    }

    /// Strings a new line, letting the oldest go when there are too many.
    add(ax: f64, ay: f64, bx: f64, by: f64): StringLine {
        let kept = 0;
        for (let i = 0; i < this.lines.length; i++) {
            if (!this.lines[i].leaving) {
                kept++;
            }
        }
        for (let i = 0; i < this.lines.length && kept >= MAX_KEPT; i++) {
            let line = this.lines[i];
            if (!line.leaving) {
                line.leaving = true;
                kept--;
            }
        }
        let line = new StringLine(ax, ay, bx, by, this.height);
        this.lines.push(line);
        return line;
    }

    advance(seconds: f64): void {
        for (let i = this.lines.length - 1; i >= 0; i--) {
            let line = this.lines[i];
            if (line.ringing) {
                line.age += seconds;
                if (!line.lively) {
                    line.ringing = false;
                }
            }
            if (line.leaving) {
                line.presence -= seconds / LET_GO;
                if (line.presence <= 0) {
                    if (this.held == line) {
                        this.held = null;
                    }
                    this.lines.splice(i, 1);
                }
            }
        }
    }

    // Rebuilds a string's path as it now stands: at rest, held aside or
    // ringing.
    private shape(line: StringLine): void {
        let dx = line.bx - line.ax;
        let dy = line.by - line.ay;
        let nx = -dy / line.length;
        let ny = dx / line.length;
        let isHeld = this.held == line;
        let path = line.path;
        path.reset();
        path.moveTo(Vector.xy(<f32>line.ax, <f32>line.ay));
        for (let i = 1; i <= PIECES; i++) {
            let along = <f64>i / <f64>PIECES;
            let aside: f64 = 0;
            if (isHeld) {
                // Two straight runs meeting where it is held.
                aside = along < this.heldAt
                    ? this.heldOffset * along / this.heldAt
                    : this.heldOffset * (1 - along) / (1 - this.heldAt);
            } else {
                aside = line.swingAt(along);
            }
            path.lineTo(Vector.xy(
                <f32>(line.ax + dx * along + nx * aside),
                <f32>(line.ay + dy * along + ny * aside)));
        }
    }

    draw(renderer: Renderer): void {
        let paint = this.paint;
        for (let i = 0; i < this.lines.length; i++) {
            let line = this.lines[i];
            this.shape(line);
            let presence = Math.max(line.presence, 0);
            // A soft glow under a fine bright core.
            paint.thickness = 7;
            paint.feather = 9;
            paint.color = Color.rgba(150, 205, 255, <i32>(70 * presence));
            renderer.drawPath(line.path, paint);
            paint.thickness = 1.6;
            paint.feather = 0;
            paint.color = Color.rgba(232, 242, 255, <i32>(235 * presence));
            renderer.drawPath(line.path, paint);
        }
        if (this.drawing) {
            let draft = this.draft;
            draft.reset();
            draft.moveTo(Vector.xy(<f32>this.startX, <f32>this.startY));
            draft.lineTo(Vector.xy(<f32>this.endX, <f32>this.endY));
            paint.thickness = 1.2;
            paint.feather = 0;
            paint.color = Color.rgba(232, 242, 255, 130);
            renderer.drawPath(draft, paint);
        }
    }
}
