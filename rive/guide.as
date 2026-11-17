// The guide: what a first visitor is shown before they know what to do.
// A string waits in the middle of the water, and a point of light, a finger
// no one holds, pulls it aside and lets it go. It makes no sound, so the
// first sound anyone hears is one they made themselves. A press anywhere
// sends the light away and leaves the string there to be taken. Once a
// string has rung, a tap on the empty water, or a long wait, shows how a
// line is drawn.
import { Color } from "rive/color";
import { Paint, PaintStyle, StrokeCap } from "rive/paint";
import { Path } from "rive/path";
import { Renderer } from "rive/renderer";
import { Vector } from "rive/vector";
import {
    Strings, StringLine, PULL_LIMIT, RELEASED_PLUCK, RELEASED_STRING, RELEASED_TAP,
    inkColor, smooth, withAlpha,
} from "./strings";

// The steps of a pluck shown.
const RESTING: i32 = 0;
// The light comes to the string.
const COMING: i32 = 1;
// It takes hold and pulls the string aside.
const PULLING: i32 = 2;
// It holds the string there a moment.
const HOLDING: i32 = 3;
// It has let go, and the string rings.
const RINGING: i32 = 4;
// Cut short while holding, it gives the string back slowly.
const EASING: i32 = 5;

// The steps of a line shown.
const NO_LINE: i32 = 0;
const DRAWING: i32 = 1;
const SHOWING: i32 = 2;
const FADING: i32 = 3;

// Seconds from the first frame to the first pluck shown.
const FIRST_WAIT: f64 = 1.0;
// Seconds each step of a pluck takes, and from one pluck to the next.
const COME: f64 = 0.7;
const PULL: f64 = 0.9;
const HOLD: f64 = 0.3;
const CYCLE: f64 = 3.8;
// Seconds after a press that rang nothing before the pluck is shown again,
// and with no press at all.
const MISSED_WAIT: f64 = 3.0;
const IDLE_WAIT: f64 = 20.0;
// Seconds the light takes to come up, to fade after a pluck, and to go when
// the visitor sends it away.
const LIGHT_IN: f64 = 0.25;
const LIGHT_OUT: f64 = 0.35;
const LIGHT_AWAY: f64 = 0.2;
// Seconds a line shown takes to be drawn, stays, and fades.
const DRAW: f64 = 0.8;
const SHOW: f64 = 0.35;
const LINE_OUT: f64 = 0.5;
// A frame that comes late moves the guide on by no more than this, and one
// step at most, so a string is never taken hold of and let go in one frame.
const MOST_STEP: f64 = 0.05;

// Times the pluck is shown again after a missed press. After that only a
// long wait brings it back.
const MOST_MISSED: i32 = 2;
// Lines shown after a long wait, at most.
const MOST_IDLE_LINES: i32 = 2;

// Where along the string the light takes hold, and how far it pulls as a
// fraction of the furthest a string can be pulled: lightly, then hard, so
// the colour can be seen to follow the strength; in between when the pluck
// is shown once.
const TAKE_AT: f64 = 0.42;
const LIGHT: f64 = 0.35;
const HARD: f64 = 0.85;
const ONCE: f64 = 0.6;
// Points from the string the light comes from.
const COME_FROM: f64 = 44;
// The size of the faint glow around the light, as drawDot takes it.
const FINGERTIP: f64 = 8;
// Points a second a string cut short is given back at: slow enough to stay
// under QUIET in main.as, so the water is left still.
const GIVE_BACK: f64 = 240;
// How much the waiting string and the lines shown lean, in radians.
const LEAN: f64 = -0.08;
// The longest line shown, in points, and how far from the edges it keeps.
const LINE_LENGTH: f64 = 160;
const MARGIN: f64 = 28;

export class Guide {
    /// The string the pluck is shown on, while it is kept.
    line: StringLine? = null;
    width: f64 = 0;
    height: f64 = 0;
    // Set once the visitor has rung a string, and once they have drawn one.
    rung: bool = false;
    drawn: bool = false;
    // Seconds since the last press or release.
    idle: f64 = 0;
    pointerDown: bool = false;
    // The pointer, up, is within reach of the waiting string.
    near: bool = false;

    // The pluck shown.
    step: i32 = RESTING;
    stepTime: f64 = 0;
    // Plucks in this showing, and shown so far.
    plucks: i32 = 0;
    plucked: i32 = 0;
    // How far aside the finger stood when the light took hold, and how far
    // it pulls, in points.
    pullFrom: f64 = 0;
    depth: f64 = 0;
    // Seconds until the next showing, below 0 for none, and its plucks.
    startIn: f64 = FIRST_WAIT;
    startPlucks: i32 = 2;
    missedShown: i32 = 0;
    // True once the first showing has run to its end.
    firstDone: bool = false;

    // The light: where it is, how bright, and how it looks.
    lightX: f64 = 0;
    lightY: f64 = 0;
    lightShown: f64 = 0;
    lightGoal: f64 = 0;
    lightFade: f64 = LIGHT_OUT;
    // Drawn as the mark under a finger holding a string, not as a hover.
    lightHolds: bool = false;

    // The line shown.
    lineStep: i32 = NO_LINE;
    lineTime: f64 = 0;
    lineShown: f64 = 0;
    lineFade: f64 = LINE_OUT;
    x0: f64 = 0;
    y0: f64 = 0;
    x1: f64 = 0;
    y1: f64 = 0;
    sinceLine: f64 = 0;
    idleLines: i32 = 0;

    path: Path = new Path();
    paint: Paint = new Paint();

    constructor() {
        this.paint.style = PaintStyle.stroke;
        this.paint.cap = StrokeCap.round;
    }

    /// Lays the waiting string out for a scene this size. The scene may
    /// still be settling on its size when it first comes up, and a phone may
    /// be turned, so until the string has been rung a new size moves it to
    /// the new middle. After that it stays where it is, as drawn ones do.
    place(width: f64, height: f64, strings: Strings): void {
        if (width <= 0 || height <= 0) {
            return;
        }
        let same = Math.abs(width - this.width) < 1 && Math.abs(height - this.height) < 1;
        this.width = width;
        this.height = height;
        let old = this.line;
        if (this.rung || (same && old != null) || (old != null && strings.held == old)) {
            return;
        }
        if (old != null) {
            strings.remove(old);
            if (this.step != RESTING) {
                // A showing under way starts again on the new string.
                this.step = RESTING;
                this.lightShown = 0;
                this.lightGoal = 0;
                this.startIn = 0.5;
                this.startPlucks = this.firstDone ? 1 : 2;
            }
        }
        let length = Math.min(0.42 * Math.max(width, height), 0.8 * width);
        let dx = 0.5 * length * Math.cos(LEAN);
        let dy = 0.5 * length * Math.sin(LEAN);
        let cx = 0.5 * width;
        let cy = 0.5 * height;
        this.line = strings.add(cx - dx, cy - dy, cx + dx, cy + dy);
    }

    /// A press came down. Call it after Strings.press.
    pressed(strings: Strings): void {
        this.pointerDown = true;
        this.near = false;
        this.idle = 0;
        this.sinceLine = 0;
        this.startIn = -1;
        let line = this.line;
        this.sendAway(!(line != null && strings.held == line));
        if (this.lineStep == DRAWING || this.lineStep == SHOWING) {
            this.lineStep = FADING;
            this.lineTime = 0;
            this.lineFade = LIGHT_AWAY;
        }
    }

    /// The press came up. Call it after Strings.release.
    released(strings: Strings): void {
        this.pointerDown = false;
        this.idle = 0;
        let what = strings.released;
        if (what == RELEASED_PLUCK) {
            if (!this.rung) {
                this.rung = true;
                this.sinceLine = 0;
            }
            this.startIn = -1;
            return;
        }
        if (what == RELEASED_STRING) {
            this.drawn = true;
        }
        if (!this.rung) {
            this.missed();
            return;
        }
        if (what == RELEASED_TAP && !this.drawn) {
            this.showLineFrom(strings.tapX, strings.tapY);
        }
    }

    /// The pointer moved while up. `near` is whether a press there would
    /// take the waiting string.
    hovering(near: bool): void {
        if (near && !this.near) {
            // Close enough to take it: a pluck being shown steps aside, and
            // the mark the strings draw under the pointer says the rest. If
            // the visitor does not take it, the pluck is shown again soon,
            // there under the pointer. A showing already owed is kept.
            let showing = this.step == COMING || this.step == PULLING || this.step == HOLDING;
            if (showing) {
                this.sendAway(true);
                if (!this.rung && this.startIn < 0) {
                    this.startIn = MISSED_WAIT;
                    this.startPlucks = 1;
                }
            }
        }
        this.near = near;
    }

    /// The pointer left the scene.
    left(): void {
        if (this.pointerDown && !this.rung) {
            this.missed();
        }
        this.pointerDown = false;
        this.near = false;
    }

    // A press that rang nothing: the pluck is shown again soon.
    private missed(): void {
        if (this.missedShown < MOST_MISSED && this.line != null) {
            this.missedShown++;
            this.startIn = MISSED_WAIT;
            this.startPlucks = 1;
        }
    }

    // Stops a pluck under way and lets the light go. Holding the string, it
    // gives it back slowly, unless the visitor has just taken it over.
    private sendAway(giveBack: bool): void {
        if (this.step == PULLING || this.step == HOLDING) {
            this.step = giveBack ? EASING : RESTING;
        } else if (this.step != EASING) {
            this.step = RESTING;
        }
        this.stepTime = 0;
        this.lightGoal = 0;
        this.lightFade = LIGHT_AWAY;
    }

    advance(seconds: f64, strings: Strings): void {
        let dt = Math.min(Math.max(seconds, 0), MOST_STEP);
        this.idle += dt;
        let line = this.line;
        if (line != null && !strings.keeps(line)) {
            // Let go to make room for newer strings.
            this.line = null;
            line = null;
            this.step = RESTING;
            this.lightGoal = 0;
            this.startIn = -1;
        }
        if (this.lightGoal > this.lightShown) {
            this.lightShown = Math.min(this.lightGoal, this.lightShown + dt / LIGHT_IN);
        } else {
            this.lightShown = Math.max(this.lightGoal, this.lightShown - dt / this.lightFade);
        }
        if (line != null) {
            if (!this.rung && this.step == RESTING && !this.pointerDown) {
                if (this.startIn >= 0) {
                    this.startIn -= dt;
                    if (this.startIn <= 0) {
                        this.startIn = -1;
                        this.begin(this.startPlucks);
                    }
                } else if (this.idle >= IDLE_WAIT) {
                    this.idle = 0;
                    this.begin(1);
                }
            }
            this.movePluck(dt, line, strings);
        }
        this.moveLine(dt, strings);
    }

    private begin(plucks: i32): void {
        this.plucks = plucks;
        this.plucked = 0;
        this.step = COMING;
        this.stepTime = 0;
    }

    // Moves a pluck shown on by `dt`, one step at most.
    private movePluck(dt: f64, line: StringLine, strings: Strings): void {
        if (this.step == RESTING) {
            return;
        }
        this.stepTime += dt;
        if (this.step == COMING) {
            if (line.heldPoint >= 0) {
                // Someone else's finger is on it.
                this.step = RESTING;
                this.lightGoal = 0;
                return;
            }
            let at = strings.pointOn(line, TAKE_AT);
            let nx = -(line.by - line.ay) / line.length;
            let ny = (line.bx - line.ax) / line.length;
            let away = COME_FROM * (1 - smooth(this.stepTime / COME));
            this.lightX = <f64>at.x + nx * away;
            this.lightY = <f64>at.y + ny * away;
            this.lightHolds = false;
            this.lightGoal = 1;
            if (this.stepTime >= COME) {
                line.hold(TAKE_AT);
                this.pullFrom = line.finger;
                let share = this.plucks >= 2 ? (this.plucked == 0 ? LIGHT : HARD) : ONCE;
                this.depth = share * line.length * PULL_LIMIT;
                this.step = PULLING;
                this.stepTime = 0;
            }
            return;
        }
        if (this.step == PULLING || this.step == HOLDING) {
            if (line.heldPoint < 0 || strings.held == line) {
                this.step = RESTING;
                this.lightGoal = 0;
                return;
            }
            let t = this.step == PULLING ? smooth(this.stepTime / PULL) : 1.0;
            line.fingerTarget = this.pullFrom + (this.depth - this.pullFrom) * t;
            let at = strings.pointOn(line, line.heldAt);
            this.lightX = <f64>at.x;
            this.lightY = <f64>at.y;
            this.lightHolds = true;
            if (this.step == PULLING && this.stepTime >= PULL) {
                this.step = HOLDING;
                this.stepTime = 0;
            } else if (this.step == HOLDING && this.stepTime >= HOLD) {
                line.letGo();
                this.plucked++;
                this.step = RINGING;
                this.stepTime = 0;
                this.lightGoal = 0;
                this.lightFade = LIGHT_OUT;
            }
            return;
        }
        if (this.step == RINGING) {
            if (this.stepTime >= CYCLE - COME - PULL - HOLD) {
                this.stepTime = 0;
                if (this.plucked < this.plucks) {
                    this.step = COMING;
                } else {
                    this.step = RESTING;
                    this.firstDone = true;
                }
            }
            return;
        }
        if (this.step == EASING) {
            if (line.heldPoint < 0 || strings.held == line) {
                this.step = RESTING;
                return;
            }
            let target = line.fingerTarget;
            let change = GIVE_BACK * dt;
            if (Math.abs(target) > change) {
                line.fingerTarget = target > 0 ? target - change : target + change;
            } else {
                line.fingerTarget = 0;
                if (Math.abs(line.finger) < 0.5) {
                    line.letGo();
                    this.step = RESTING;
                }
            }
        }
    }

    // Shows a line drawn from (x, y), toward the middle of the scene.
    private showLineFrom(x: f64, y: f64): void {
        if (this.lineStep == DRAWING || this.lineStep == SHOWING) {
            return;
        }
        let length = Math.min(LINE_LENGTH, 0.35 * Math.min(this.width, this.height));
        let toward = x < 0.5 * this.width ? 1.0 : -1.0;
        let x1 = x + toward * length * Math.cos(LEAN);
        let y1 = y + length * Math.sin(LEAN);
        this.startLine(x, y,
            Math.min(Math.max(x1, MARGIN), this.width - MARGIN),
            Math.min(Math.max(y1, MARGIN), this.height - MARGIN));
    }

    // Shows a line where the water is emptiest.
    private showLineWhereEmpty(strings: Strings): void {
        let bestX = 0.5 * this.width;
        let bestY = 0.25 * this.height;
        let bestRoom: f64 = -1;
        for (let i = 0; i < 8; i++) {
            let fx = i < 2 ? 0.5 : (i < 4 ? (i == 2 ? 0.2 : 0.8) : (i % 2 == 0 ? 0.27 : 0.73));
            let fy = i < 2 ? (i == 0 ? 0.22 : 0.78) : (i < 4 ? 0.5 : (i < 6 ? 0.27 : 0.73));
            let x = fx * this.width;
            let y = fy * this.height;
            let room = Infinity;
            for (let s = 0; s < strings.lines.length; s++) {
                let line = strings.lines[s];
                if (!line.leaving) {
                    room = Math.min(room, distanceTo(x, y, line));
                }
            }
            if (room > bestRoom) {
                bestRoom = room;
                bestX = x;
                bestY = y;
            }
        }
        let half = 0.5 * Math.min(LINE_LENGTH, 0.35 * Math.min(this.width, this.height));
        let dx = half * Math.cos(LEAN);
        let dy = half * Math.sin(LEAN);
        this.startLine(bestX - dx, bestY - dy, bestX + dx, bestY + dy);
    }

    private startLine(x0: f64, y0: f64, x1: f64, y1: f64): void {
        this.x0 = x0;
        this.y0 = y0;
        this.x1 = x1;
        this.y1 = y1;
        this.lineStep = DRAWING;
        this.lineTime = 0;
        this.lineShown = 0;
    }

    // Moves a line shown on by `dt`, and starts one after a long wait.
    private moveLine(dt: f64, strings: Strings): void {
        if (this.rung && !this.drawn && this.lineStep == NO_LINE && !this.pointerDown) {
            this.sinceLine += dt;
            if (this.sinceLine >= IDLE_WAIT && this.idleLines < MOST_IDLE_LINES) {
                this.sinceLine = 0;
                this.idleLines++;
                this.showLineWhereEmpty(strings);
            }
        }
        if (this.lineStep == NO_LINE) {
            return;
        }
        if (this.drawn && this.lineStep != FADING) {
            this.lineStep = FADING;
            this.lineTime = 0;
            this.lineFade = LIGHT_AWAY;
        }
        this.lineTime += dt;
        if (this.lineStep == DRAWING) {
            this.lineShown = Math.min(1, this.lineShown + dt / LIGHT_IN);
            if (this.lineTime >= DRAW) {
                this.lineStep = SHOWING;
                this.lineTime = 0;
            }
        } else if (this.lineStep == SHOWING) {
            if (this.lineTime >= SHOW) {
                this.lineStep = FADING;
                this.lineTime = 0;
                this.lineFade = LINE_OUT;
            }
        } else {
            this.lineShown = Math.max(0, this.lineShown - dt / this.lineFade);
            if (this.lineShown <= 0) {
                this.lineStep = NO_LINE;
            }
        }
    }

    draw(renderer: Renderer, strings: Strings): void {
        let paint = this.paint;
        if (this.lineStep != NO_LINE && this.lineShown > 0.01) {
            let shown = smooth(this.lineShown);
            let reach = this.lineStep == DRAWING ? smooth(this.lineTime / DRAW) : 1.0;
            let ex = this.x0 + (this.x1 - this.x0) * reach;
            let ey = this.y0 + (this.y1 - this.y0) * reach;
            let path = this.path;
            path.reset();
            path.moveTo(Vector.xy(<f32>this.x0, <f32>this.y0));
            path.lineTo(Vector.xy(<f32>ex, <f32>ey));
            paint.thickness = 1.2;
            paint.feather = 0;
            paint.color = Color.rgba(232, 242, 255, <i32>(110 * shown));
            renderer.drawPath(path, paint);
            strings.drawDot(renderer, Vector.xy(<f32>ex, <f32>ey), 2.4 * shown,
                Color.rgba(150, 205, 255, <i32>(110 * shown)),
                Color.rgba(232, 242, 255, <i32>(200 * shown)));
        }
        let shown = smooth(this.lightShown);
        if (shown <= 0.01) {
            return;
        }
        // The marks the strings draw under a real pointer, with a wide, faint
        // glow around them like a fingertip's, so the light reads as
        // something touching the string, not as part of it.
        let at = Vector.xy(<f32>this.lightX, <f32>this.lightY);
        let line = this.line;
        if (this.lightHolds && line != null) {
            let heat = inkColor(0.15 + 0.7 * line.tension);
            strings.drawDot(renderer, at, FINGERTIP, withAlpha(heat, <i32>(45 * shown)), Color.rgba(0, 0, 0, 0));
            strings.drawDot(renderer, at, 3.4 + 1.5 * line.tension,
                withAlpha(heat, <i32>(160 * shown)),
                Color.rgba(255, 252, 245, <i32>(255 * shown)));
        } else {
            strings.drawDot(renderer, at, FINGERTIP, Color.rgba(150, 205, 255, <i32>(45 * shown)), Color.rgba(0, 0, 0, 0));
            strings.drawDot(renderer, at, 3.2 * shown,
                Color.rgba(150, 205, 255, <i32>(130 * shown)),
                Color.rgba(232, 242, 255, <i32>(220 * shown)));
        }
    }
}

// How far the point is from a string's rest line, in points.
function distanceTo(x: f64, y: f64, line: StringLine): f64 {
    let dx = line.bx - line.ax;
    let dy = line.by - line.ay;
    let along = Math.min(Math.max(((x - line.ax) * dx + (y - line.ay) * dy) / (line.length * line.length), 0), 1);
    let px = line.ax + dx * along - x;
    let py = line.ay + dy * along - y;
    return Math.sqrt(px * px + py * py);
}
