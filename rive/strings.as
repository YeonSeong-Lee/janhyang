// The strings: lines the player draws across the surface, pulled aside and
// let go to ring.
import { Color } from "rive/color";
import { Paint, PaintStyle, StrokeCap, StrokeJoin } from "rive/paint";
import { Path } from "rive/path";
import { Renderer } from "rive/renderer";
import { Vector } from "rive/vector";

/// The most strings kept; drawing one more lets the oldest go.
export const MAX_KEPT: i32 = 12;

// Points from a string within which a press takes hold of it, and within
// which the pointer, not pressed, marks where it would.
const GRAB_REACH: f64 = 24;
// A line shorter than this, in points, is a tap and makes no string.
const SHORTEST: f64 = 40;
// How far a string is pulled aside for its loudest note, as a fraction of
// its length. Up to PULL_GIVE of that it follows the pointer exactly; past
// it the string pushes back harder the further it goes and never passes
// PULL_MOST, so the hand feels the limit coming instead of hitting a wall.
export const PULL_LIMIT: f64 = 0.22;
const PULL_GIVE: f64 = 0.6;
const PULL_MOST: f64 = 1.25;
// Seconds the look of a string's tension takes to ease off once it goes
// slack, and a hover mark to come or go.
const EASE_TENSION: f64 = 0.35;
const EASE_HOVER: f64 = 0.12;
// Seconds a string let go takes to fade away.
const LET_GO: f64 = 0.9;
// Seconds a line let go too short takes to draw back into its start.
const SHRINK: f64 = 0.25;
/// Points along a string at which its shape and motion are handed to the
/// surface, ends included. sim.wgsl holds the same number.
export const SAMPLES: i32 = 32;
// About how many pieces a string is simulated and drawn with.
const PIECES: f64 = 48;
// How far a wave runs in one step of a string's own, in pieces. Just under 1
// keeps a running corner nearly as sharp as on a real string; exactly 1
// would let every other point drift apart into a fine zigzag.
const COURANT: f64 = 0.95;
/// Seconds one step of a string's motion covers; the surface steps the same.
export const STRING_STEP: f64 = 1.0 / 240.0;
// How quickly a held point follows the finger, per second. A finger is soft:
// a jump of the pointer pulls the string over a few hundredths of a second.
const FINGER: f64 = 45;
// Losses. The whole string loses its swing to the air at a rate that grows
// with how fast it swings; the sharp detail of its shape is lost sooner,
// which rounds a running corner off as the note fades.
const AIR: f64 = 0.5;
const AIR_PER_SWING: f64 = 0.05;
const STIFFNESS_LOSS: f64 = 0.02;
// Below this, in points, a string let go is taken as still.
const STILL: f64 = 0.05;

/// What the last release came to: nothing, a string rung, a new string
/// drawn, or a tap on the water too short to be a string.
export const RELEASED_NOTHING: i32 = 0;
export const RELEASED_PLUCK: i32 = 1;
export const RELEASED_STRING: i32 = 2;
export const RELEASED_TAP: i32 = 3;

/// The pitch in Hz a string of `length` sounds, in a scene `height` tall.
/// Doubling its length lowers it by an octave. No note or chord snapping.
export function pitchOf(length: f64, height: f64): f64 {
    return 220 * Math.max(height, 1) / Math.max(length, 1);
}

/// A string: a line of points held at both ends, each pulled toward its
/// neighbours by the string's tension. Its motion is worked out step by
/// step from that pull (the wave equation), so whatever is done to it - a
/// pull, a pluck, a finger laid on it while it rings - it answers as a real
/// string would.
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

    /// Pieces it is simulated with, and steps of its own each STRING_STEP
    /// is split into; a wave runs just under one piece per step.
    pieces: i32 = 48;
    substeps: i32 = 2;
    /// How far each point stands from rest, in points to one side, now and
    /// one step of its own before.
    now: StaticArray<f64>;
    before: StaticArray<f64>;
    // Scratch for the next step.
    next: StaticArray<f64>;
    // Loss per step of its own, as the fraction of the swing kept.
    keep: f64 = 1;
    // How strongly a point is drawn toward its neighbours each step of its
    // own: the square of how many pieces a wave runs a step.
    pull: f64 = 0.9;

    /// True while it moves or is held; a still string is not stepped.
    awake: bool = false;
    /// The point a finger holds, or -1, and where the finger is.
    heldPoint: i32 = -1;
    fingerTarget: f64 = 0;
    finger: f64 = 0;
    /// Steps taken while held; none means the pull was never seen moving.
    stepsHeld: i32 = 0;

    /// Points it moves in a STRING_STEP at the most when let go from its
    /// furthest pull at the middle: a corner runs at twice its length times
    /// its swings a second, and moves the string as fast as the slope it
    /// leaves.
    get fullSpeed(): f64 {
        return 4 * PULL_LIMIT * this.length * this.rate * STRING_STEP;
    }

    /// How taut it looks, 0 to 1: how far it stands aside for its length,
    /// rising at once and easing off as it goes slack, so a ringing string
    /// does not flicker as it passes through its rest line.
    tension: f64 = 0;

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
        // Store the pitch once: resizing or changing a reference chord must
        // never change an instrument the player has already made.
        this.frequency = pitchOf(this.length, height);
        // Keep the deliberately slowed visual simulation stable even for
        // very low notes; the audible frequency above stays untouched.
        this.rate = Math.max(2, 5 + 2.4 * Math.log2(this.frequency / 65));
        // A wave crosses the string and back once per swing. Pick whole
        // steps per STRING_STEP, then the piece count that makes the wave run
        // just under COURANT pieces a step.
        let substeps = <i32>Math.max(1, Math.ceil(2 * PIECES * this.rate * STRING_STEP / COURANT));
        let pieces = <i32>Math.max(24, Math.floor(COURANT * <f64>substeps / (2 * this.rate * STRING_STEP)));
        this.substeps = substeps;
        this.pieces = pieces;
        let courant = 2 * <f64>pieces * this.rate * STRING_STEP / <f64>substeps;
        this.pull = courant * courant;
        this.now = new StaticArray<f64>(pieces + 1);
        this.before = new StaticArray<f64>(pieces + 1);
        this.next = new StaticArray<f64>(pieces + 1);
        let dt = STRING_STEP / <f64>substeps;
        // The scheme below loses (1 - keep) / 2 of the swing a step each way,
        // so the swing fades at AIR + rate * AIR_PER_SWING per second.
        this.keep = Math.exp(-2 * dt * (AIR + this.rate * AIR_PER_SWING));
    }

    // Where it stood at SAMPLES points along it when last handed to the
    // surface, a STRING_STEP ago.
    sampled: StaticArray<f64> = new StaticArray<f64>(SAMPLES);

    /// How far the string stands from rest at `along`, 0 to 1, in points.
    swingAt(along: f64): f64 {
        let f = Math.min(Math.max(along, 0), 1) * <f64>this.pieces;
        let i = <i32>Math.min(Math.floor(f), <f64>(this.pieces - 1));
        let part = f - <f64>i;
        return this.now[i] + (this.now[i + 1] - this.now[i]) * part;
    }

    /// Lays a finger on the string at `along`, where it stands now.
    hold(along: f64): void {
        let point = <i32>Math.round(along * <f64>this.pieces);
        this.heldPoint = <i32>Math.min(Math.max(point, 1), this.pieces - 1);
        this.finger = this.now[this.heldPoint];
        this.fingerTarget = this.finger;
        this.stepsHeld = 0;
        if (!this.awake) {
            for (let i = 0; i < SAMPLES; i++) {
                this.sampled[i] = 0;
            }
        }
        this.awake = true;
    }

    /// Where along it, 0 to 1, the finger is.
    get heldAt(): f64 {
        return <f64>this.heldPoint / <f64>this.pieces;
    }

    /// Takes the finger away and lets the string go from where it stands.
    letGo(): void {
        if (this.heldPoint < 0) {
            return;
        }
        // Not stepped while held, as when frames come late: it stands as a
        // held string at rest does, straight from each end to the finger.
        if (this.stepsHeld == 0) {
            let p = this.heldPoint;
            for (let i = 0; i <= this.pieces; i++) {
                let aside = i <= p
                    ? this.fingerTarget * <f64>i / <f64>p
                    : this.fingerTarget * <f64>(this.pieces - i) / <f64>(this.pieces - p);
                this.now[i] = aside;
                this.before[i] = aside;
            }
        }
        this.heldPoint = -1;
    }

    /// Moves the string on by one STRING_STEP.
    step(): void {
        if (!this.awake) {
            return;
        }
        let n = this.pieces;
        let now = this.now;
        let before = this.before;
        let next = this.next;
        let keep = this.keep;
        let held = this.heldPoint;
        if (held >= 0) {
            this.stepsHeld++;
        }
        let fingerStart = this.finger;
        let fingerEnd = fingerStart + (this.fingerTarget - fingerStart) * (1 - Math.exp(-STRING_STEP * FINGER));
        this.finger = fingerEnd;
        for (let s = 0; s < this.substeps; s++) {
            // Tension pulls each point toward its neighbours; it keeps going
            // as it was going, less what the air takes.
            let pull = this.pull;
            let carry = 0.5 * (1 + keep);
            for (let i = 1; i < n; i++) {
                let here = now[i];
                next[i] = (2 * here + pull * (now[i - 1] - 2 * here + now[i + 1])) * carry
                    - before[i] * keep;
            }
            next[0] = 0;
            next[n] = 0;
            if (held >= 0) {
                next[held] = fingerStart + (fingerEnd - fingerStart) * <f64>(s + 1) / <f64>this.substeps;
            }
            for (let i = 0; i <= n; i++) {
                before[i] = now[i];
                now[i] = next[i];
            }
        }
        // The fine detail of the shape fades sooner than the whole swing.
        for (let pass = 0; pass < 2; pass++) {
            let row = pass == 0 ? now : before;
            let last = row[0];
            for (let i = 1; i < n; i++) {
                let here = row[i];
                if (i != held) {
                    row[i] = here + STIFFNESS_LOSS * (last - 2 * here + row[i + 1]);
                }
                last = here;
            }
        }
        let peak: f64 = 0;
        for (let i = 0; i <= n; i++) {
            peak = Math.max(peak, Math.abs(now[i]));
        }
        let taut = Math.min(peak / (this.length * PULL_LIMIT), 1);
        this.tension = Math.max(taut, this.tension * Math.exp(-STRING_STEP / EASE_TENSION));
        if (held < 0) {
            let largest: f64 = 0;
            for (let i = 0; i <= n; i++) {
                largest = Math.max(largest, Math.max(Math.abs(now[i]), Math.abs(before[i])));
            }
            if (largest < STILL && this.tension < 0.01) {
                for (let i = 0; i <= n; i++) {
                    now[i] = 0;
                    before[i] = 0;
                }
                this.tension = 0;
                this.awake = false;
            }
        }
    }

    /// Writes where the string stands now and where it stood a STRING_STEP
    /// before, in points to one side, at SAMPLES points along it, ends
    /// included. Between the two lies the water it swept through.
    sample(offsets: StaticArray<f32>, previous: StaticArray<f32>): void {
        for (let i = 0; i < SAMPLES; i++) {
            let along = <f64>i / <f64>(SAMPLES - 1);
            let here = this.swingAt(along);
            offsets[i] = <f32>here;
            previous[i] = <f32>this.sampled[i];
            this.sampled[i] = here;
        }
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

    get previewFrequency(): f64 {
        if (!this.drawing) return 0;
        let dx = this.endX - this.startX;
        let dy = this.endY - this.startY;
        let length = Math.sqrt(dx * dx + dy * dy);
        return length >= SHORTEST ? pitchOf(length, this.height) : 0;
    }

    // A line being drawn.
    drawing: bool = false;
    startX: f64 = 0;
    startY: f64 = 0;
    endX: f64 = 0;
    endY: f64 = 0;
    draft: Path = new Path();
    // A line let go too short to be a string, drawing back into where it
    // started: 1 as it is let go, falling to 0.
    shrink: f64 = 0;
    shrinkX: f64 = 0;
    shrinkY: f64 = 0;

    // A string being held aside, and how far aside the finger holds it.
    held: StringLine? = null;
    heldOffset: f64 = 0;

    // The string a press at the pointer would take hold of, and where along
    // it; `hoverShown` eases in and out so the mark does not blink.
    hovered: StringLine? = null;
    hoverAlong: f64 = 0;
    hoverShown: f64 = 0;
    // The string the hover mark was last drawn on, kept while it fades.
    hoverDrawn: StringLine? = null;
    // How far the held point has come in, for the mark under the finger.
    gripShown: f64 = 0;

    struck: Struck = new Struck();
    /// What the last release came to, one of the RELEASED_ values, and for
    /// a tap, where it fell.
    released: i32 = RELEASED_NOTHING;
    tapX: f64 = 0;
    tapY: f64 = 0;
    paint: Paint = new Paint();
    dot: Path = new Path();

    constructor() {
        this.paint.style = PaintStyle.stroke;
        this.paint.cap = StrokeCap.round;
        this.paint.join = StrokeJoin.round;
    }

    // The nearest string within `reach` of the point where it stands now,
    // or null; `nearAlong` is set to where along it.
    private nearAlong: f64 = 0;
    private nearest(x: f64, y: f64, reach: f64): StringLine? {
        let best: StringLine? = null;
        let bestAlong: f64 = 0;
        let bestDistance: f64 = reach;
        for (let i = 0; i < this.lines.length; i++) {
            let line = this.lines[i];
            if (line.leaving) {
                continue;
            }
            let dx = (line.bx - line.ax) / line.length;
            let dy = (line.by - line.ay) / line.length;
            let rawAlong = ((x - line.ax) * dx + (y - line.ay) * dy) / line.length;
            let along = Math.min(Math.max(rawAlong, 0.06), 0.94);
            let across = (x - line.ax) * -dy + (y - line.ay) * dx;
            let aside = across - line.swingAt(along);
            let beyond = (rawAlong - along) * line.length;
            let distance = Math.sqrt(aside * aside + beyond * beyond);
            if (distance < bestDistance) {
                bestDistance = distance;
                best = line;
                bestAlong = along;
            }
        }
        this.nearAlong = bestAlong;
        return best;
    }

    // Takes hold of the nearest string within reach of the point, if any,
    // where it stands now: a ringing string is caught mid swing.
    private take(x: f64, y: f64): bool {
        let best = this.nearest(x, y, GRAB_REACH);
        if (best == null) {
            return false;
        }
        best.hold(this.nearAlong);
        this.held = best;
        this.heldOffset = best.fingerTarget;
        return true;
    }

    // Moves the finger on the held string to follow the pointer, to one side
    // of the string and no further than it can stretch.
    private pull(x: f64, y: f64): void {
        let line = this.held;
        if (line == null) {
            return;
        }
        let dx = (line.bx - line.ax) / line.length;
        let dy = (line.by - line.ay) / line.length;
        let px = line.ax + (line.bx - line.ax) * line.heldAt;
        let py = line.ay + (line.by - line.ay) * line.heldAt;
        let offset = (x - px) * -dy + (y - py) * dx;
        let limit = line.length * PULL_LIMIT;
        this.heldOffset = resist(offset, limit);
        line.fingerTarget = this.heldOffset;
    }

    /// The pointer moved while up: marks the string a press would take.
    hover(x: f64, y: f64): void {
        let line = this.nearest(x, y, GRAB_REACH);
        this.hovered = line;
        if (line != null) {
            this.hoverAlong = this.nearAlong;
            this.hoverDrawn = line;
        }
    }

    /// The pointer left or went down: no string is marked.
    unhover(): void {
        this.hovered = null;
    }

    /// A press at the point: takes hold of a string there, or starts a line.
    press(x: f64, y: f64): void {
        this.cancel();
        this.hovered = null;
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
        this.released = RELEASED_NOTHING;
        let line = this.held;
        if (line != null) {
            this.pull(x, y);
            this.held = null;
            line.letGo();
            let limit = line.length * PULL_LIMIT;
            let strength = Math.min(Math.abs(this.heldOffset) / limit, 1);
            if (strength < 0.03) {
                return null;
            }
            this.released = RELEASED_PLUCK;
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
                this.released = RELEASED_STRING;
            } else {
                this.released = RELEASED_TAP;
                this.tapX = this.startX;
                this.tapY = this.startY;
                // Seen to draw back, so a line too short reads as too short.
                this.shrink = 1;
                this.shrinkX = this.endX;
                this.shrinkY = this.endY;
            }
        }
        return null;
    }

    /// The pointer left: whatever was in hand is dropped without a sound.
    cancel(): void {
        this.released = RELEASED_NOTHING;
        this.drawing = false;
        let line = this.held;
        if (line != null) {
            line.letGo();
        }
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

    /// Takes a string away at once, without letting it fade.
    remove(line: StringLine): void {
        for (let i = this.lines.length - 1; i >= 0; i--) {
            if (this.lines[i] == line) {
                this.lines.splice(i, 1);
            }
        }
        if (this.held == line) {
            this.held = null;
        }
        if (this.hovered == line) {
            this.hovered = null;
        }
        if (this.hoverDrawn == line) {
            this.hoverDrawn = null;
        }
    }

    /// True while the string is among those kept.
    keeps(line: StringLine): bool {
        if (line.leaving) {
            return false;
        }
        for (let i = 0; i < this.lines.length; i++) {
            if (this.lines[i] == line) {
                return true;
            }
        }
        return false;
    }

    /// Moves every moving string on by one STRING_STEP.
    step(): void {
        for (let i = 0; i < this.lines.length; i++) {
            this.lines[i].step();
        }
    }

    advance(seconds: f64): void {
        let hoverGoal = this.hovered != null ? 1.0 : 0.0;
        this.hoverShown = ease(this.hoverShown, hoverGoal, seconds, EASE_HOVER);
        let gripGoal = this.held != null ? 1.0 : 0.0;
        this.gripShown = ease(this.gripShown, gripGoal, seconds, EASE_HOVER);
        this.shrink = Math.max(0, this.shrink - seconds / SHRINK);
        for (let i = this.lines.length - 1; i >= 0; i--) {
            let line = this.lines[i];
            if (line.leaving) {
                line.presence -= seconds / LET_GO;
                if (line.presence <= 0) {
                    if (this.held == line) {
                        this.held = null;
                    }
                    if (this.hovered == line) {
                        this.hovered = null;
                    }
                    if (this.hoverDrawn == line) {
                        this.hoverDrawn = null;
                    }
                    this.lines.splice(i, 1);
                }
            }
        }
    }

    // Rebuilds a string's path through its points as they now stand.
    private shape(line: StringLine): void {
        let dx = line.bx - line.ax;
        let dy = line.by - line.ay;
        let nx = -dy / line.length;
        let ny = dx / line.length;
        let path = line.path;
        let pieces = line.pieces;
        let now = line.now;
        path.reset();
        path.moveTo(Vector.xy(<f32>line.ax, <f32>line.ay));
        for (let i = 1; i <= pieces; i++) {
            let along = <f64>i / <f64>pieces;
            let aside = now[i];
            path.lineTo(Vector.xy(
                <f32>(line.ax + dx * along + nx * aside),
                <f32>(line.ay + dy * along + ny * aside)));
        }
    }

    /// Where a string stands at `along`, 0 to 1, in the scene.
    pointOn(line: StringLine, along: f64): Vector {
        let aside = line.swingAt(along);
        return Vector.xy(
            <f32>(line.ax + (line.bx - line.ax) * along - (line.by - line.ay) / line.length * aside),
            <f32>(line.ay + (line.by - line.ay) * along + (line.bx - line.ax) / line.length * aside));
    }

    /// A round mark at `at`: a soft halo and a bright centre.
    drawDot(renderer: Renderer, at: Vector, size: f64, glow: Color, core: Color): void {
        let dot = this.dot;
        let paint = this.paint;
        dot.reset();
        dot.moveTo(at);
        dot.lineTo(Vector.xy(at.x + 0.01, at.y));
        paint.thickness = <f32>(size * 3.2);
        paint.feather = <f32>(size * 3);
        paint.color = glow;
        renderer.drawPath(dot, paint);
        paint.thickness = <f32>size;
        paint.feather = 0;
        paint.color = core;
        renderer.drawPath(dot, paint);
    }

    /// An open ring reads as a place to grab; a smaller ring closes on press.
    drawGrip(renderer: Renderer, at: Vector, radius: f64, alpha: f64): void {
        let path = this.dot;
        path.reset();
        for (let i = 0; i <= 32; i++) {
            let angle = <f64>i * Math.PI * 2 / 32;
            let point = Vector.xy(at.x + <f32>(Math.cos(angle) * radius),
                at.y + <f32>(Math.sin(angle) * radius));
            if (i == 0) path.moveTo(point);
            else path.lineTo(point);
        }
        this.paint.feather = 0;
        this.paint.thickness = 1.5;
        this.paint.color = Color.rgba(220, 239, 255, <i32>(220 * alpha));
        renderer.drawPath(path, this.paint);
    }

    draw(renderer: Renderer): void {
        let paint = this.paint;
        let hoverDrawn = this.hoverDrawn;
        let hoverShown = smooth(this.hoverShown);
        for (let i = 0; i < this.lines.length; i++) {
            let line = this.lines[i];
            this.shape(line);
            let presence = Math.max(line.presence, 0);
            // Taut, the string takes on the colour the ink it leaves will
            // have, cold to hot, and burns brighter and finer; a string the
            // pointer is over lifts a little.
            let tension = line.tension;
            let lift = hoverDrawn == line && this.held == null ? hoverShown : 0;
            let heat = inkColor(0.15 + 0.7 * tension);
            let glowAlpha = (70 + 40 * lift + 120 * tension) * presence;
            paint.thickness = <f32>(7 + 5 * tension);
            paint.feather = <f32>(9 + 6 * tension);
            paint.color = Color.lerp(Color.rgba(150, 205, 255, <i32>glowAlpha),
                withAlpha(heat, <i32>glowAlpha),
                <f32>Math.min(tension * 1.6, 1));
            renderer.drawPath(line.path, paint);
            paint.thickness = <f32>(1.6 - 0.4 * tension + 0.3 * lift);
            paint.feather = 0;
            paint.color = Color.lerp(Color.rgba(232, 242, 255, <i32>(235 * presence)),
                Color.rgba(255, 252, 245, <i32>(255 * presence)), <f32>tension);
            renderer.drawPath(line.path, paint);
        }
        // Under the finger, the point it holds the string by.
        let held = this.held;
        let grip = smooth(this.gripShown);
        if (held != null && grip > 0.01) {
            let at = this.pointOn(held, held.heldAt);
            let heat = inkColor(0.15 + 0.7 * held.tension);
            this.drawGrip(renderer, at, 6 + 4 * (1 - grip), grip);
            this.drawDot(renderer, at, 3 + 1.5 * held.tension,
                withAlpha(heat, <i32>(150 * grip)),
                Color.rgba(255, 252, 245, <i32>(255 * grip)));
        }
        // Where a press would take hold.
        if (hoverDrawn != null && held == null && hoverShown > 0.01 && !this.drawing) {
            let at = this.pointOn(hoverDrawn, this.hoverAlong);
            this.drawGrip(renderer, at, 11 + 3 * (1 - hoverShown), hoverShown);
            this.drawDot(renderer, at, 2.4 * hoverShown,
                Color.rgba(150, 205, 255, <i32>(110 * hoverShown)),
                Color.rgba(232, 242, 255, <i32>(200 * hoverShown)));
        }
        if (this.drawing) {
            // Faint while too short to be a string, brightening as it gets
            // long enough.
            let dx = this.endX - this.startX;
            let dy = this.endY - this.startY;
            let enough = smooth((Math.sqrt(dx * dx + dy * dy) - 0.7 * SHORTEST) / (0.3 * SHORTEST));
            let draft = this.draft;
            draft.reset();
            draft.moveTo(Vector.xy(<f32>this.startX, <f32>this.startY));
            draft.lineTo(Vector.xy(<f32>this.endX, <f32>this.endY));
            paint.thickness = <f32>(1.0 + 0.3 * enough);
            paint.feather = 0;
            paint.color = Color.rgba(232, 242, 255, <i32>(70 + 80 * enough));
            renderer.drawPath(draft, paint);
        } else if (this.shrink > 0) {
            let left = smooth(this.shrink);
            let draft = this.draft;
            draft.reset();
            draft.moveTo(Vector.xy(<f32>this.startX, <f32>this.startY));
            draft.lineTo(Vector.xy(
                <f32>(this.startX + (this.shrinkX - this.startX) * left),
                <f32>(this.startY + (this.shrinkY - this.startY) * left)));
            paint.thickness = 1.0;
            paint.feather = 0;
            paint.color = Color.rgba(232, 242, 255, <i32>(70 * left));
            renderer.drawPath(draft, paint);
        }
    }
}

// How far aside a string stands when the pointer is `offset` from it: the
// same up to PULL_GIVE of `limit`, then giving less and less ground, so it
// reaches `limit` only well past it and PULL_MOST of it never.
function resist(offset: f64, limit: f64): f64 {
    let give = limit * PULL_GIVE;
    let span = limit * (PULL_MOST - PULL_GIVE);
    let size = Math.abs(offset);
    if (size <= give) {
        return offset;
    }
    let over = (size - give) / span;
    let held = give + span * (1 - 1 / (1 + over));
    return offset < 0 ? -held : held;
}

// Moves `from` toward `to`, closing most of the gap in about `time` seconds.
function ease(from: f64, to: f64, seconds: f64, time: f64): f64 {
    return to + (from - to) * Math.exp(-seconds * 3 / time);
}

export function smooth(t: f64): f64 {
    let c = Math.min(Math.max(t, 0), 1);
    return c * c * (3 - 2 * c);
}

// The ink's colours, cold to hot, as show.wgsl paints them: deep blue, cyan,
// amber, near white.
export function inkColor(amount: f64): Color {
    let a = Math.min(Math.max(amount, 0), 1);
    if (a < 0.33) {
        return Color.lerp(Color.rgb(13, 89, 242), Color.rgb(26, 217, 230), <f32>(a / 0.33));
    }
    if (a < 0.66) {
        return Color.lerp(Color.rgb(26, 217, 230), Color.rgb(255, 158, 38), <f32>((a - 0.33) / 0.33));
    }
    return Color.lerp(Color.rgb(255, 158, 38), Color.rgb(255, 242, 217), <f32>((a - 0.66) / 0.34));
}

export function withAlpha(color: Color, alpha: i32): Color {
    return Color.rgba(<i32>Color.red(color), <i32>Color.green(color), <i32>Color.blue(color), alpha);
}
