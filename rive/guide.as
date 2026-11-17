// The guide: what a first visitor is shown before they know what to do.
// A string waits in the middle of the water, and a mouse pointer no one
// holds comes to it, clicks, drags the string aside faster and faster and
// lets go on the move, as if throwing it. It makes no sound, so the first
// sound anyone hears is one they made themselves. A press anywhere sends
// the pointer away and leaves the string there to be taken. Once a string
// has rung, a tap on the empty water, or a long wait, shows the same
// pointer drawing a line.
import { Color } from "rive/color";
import { Paint, PaintStyle, StrokeCap, StrokeJoin } from "rive/paint";
import { Path } from "rive/path";
import { Renderer } from "rive/renderer";
import { Vector } from "rive/vector";
import {
    Strings, StringLine, PULL_LIMIT, RELEASED_PLUCK, RELEASED_STRING, RELEASED_TAP,
    inkColor, smooth, withAlpha,
} from "./strings";

// The steps of a pluck shown.
const RESTING: i32 = 0;
// The pointer comes to the string: from aside the first time, and after
// that from where it last let go.
const COMING: i32 = 1;
// It clicks, taking hold of the string, and grips it a moment.
const PRESSING: i32 = 2;
// It drags the string aside, faster and faster, and lets go on the move.
const THROWING: i32 = 3;
// Let go, it carries on a little the way it was going.
const FOLLOWING: i32 = 4;
// It waits while the string rings, before the next pluck.
const WAITING: i32 = 5;
// The showing over, it fades away.
const LEAVING: i32 = 6;
// Cut short while holding, it gives the string back slowly.
const EASING: i32 = 7;

// The steps of a line shown.
const NO_LINE: i32 = 0;
const DRAWING: i32 = 1;
const SHOWING: i32 = 2;
const FADING: i32 = 3;

// Seconds from the first frame to the first pluck shown.
const FIRST_WAIT: f64 = 1.0;
// Seconds each step of a pluck takes: coming in from aside, coming back for
// the next pluck, gripping, dragging until let go, carrying on, waiting
// while the string rings, and fading away.
const ENTER: f64 = 0.9;
const RETURN: f64 = 0.6;
const PRESS: f64 = 0.18;
const THROW: f64 = 0.55;
const FOLLOW: f64 = 0.35;
const WAIT: f64 = 1.3;
const LEAVE: f64 = 0.5;
// Seconds after a press that rang nothing before the pluck is shown again,
// and with no press at all.
const MISSED_WAIT: f64 = 3.0;
const IDLE_WAIT: f64 = 20.0;
// Seconds the pointer takes to appear, and to go when the visitor sends it
// away.
const POINTER_IN: f64 = 0.2;
const POINTER_AWAY: f64 = 0.2;
// Seconds a click takes to press in or come back out, and the ring it
// leaves takes to spread and fade.
const CLICK: f64 = 0.08;
const RING: f64 = 0.45;
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

// Where along the string the pointer takes hold, and how far it drags as a
// fraction of the furthest a string can be pulled: lightly, then hard, so
// the colour can be seen to follow the strength; in between when the pluck
// is shown once.
const TAKE_AT: f64 = 0.42;
const LIGHT: f64 = 0.35;
const HARD: f64 = 0.85;
const ONCE: f64 = 0.6;
// Where the pointer first comes from, from where it takes hold: below and
// to the right, as a hand on a mouse brings it in.
const ENTER_X: f64 = 130;
const ENTER_Y: f64 = 105;
// Seconds over which the pointer's carry after letting go dies away.
const CARRY: f64 = 0.11;
// Points within which the string marks where the coming pointer would take
// hold, as it does under a real one.
const REACH: f64 = 24;
// Points a second a string cut short is given back at: slow enough to stay
// under QUIET in main.as, so the water is left still.
const GIVE_BACK: f64 = 240;
// How much the waiting string and the lines shown lean, in radians.
const LEAN: f64 = -0.08;
// The longest line shown, in points, and how far from the edges it keeps.
const LINE_LENGTH: f64 = 160;
const MARGIN: f64 = 28;

// The pointer: an arrow with its tip at 0, 0, y down, in points, about 20
// tall, and how far it shrinks while pressed. Its corners go clockwise on
// screen, as a fill and a feathered fill need under the default rule.
const ARROW_X: StaticArray<f64> = [0, 13.0, 7.4, 10.3, 7.3, 4.3, 0];
const ARROW_Y: StaticArray<f64> = [0, 12.5, 12.5, 19.1, 20.4, 13.6, 17.5];
const PRESSED: f64 = 0.12;
// How far a quarter circle's control points stand from its ends, for a
// ring drawn as four curves.
const KAPPA: f64 = 0.5523;

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
    // The real pointer, up, is within reach of the waiting string.
    near: bool = false;

    // The pluck shown.
    step: i32 = RESTING;
    stepTime: f64 = 0;
    // Seconds this coming takes: from aside, or back for the next pluck.
    comeTime: f64 = ENTER;
    // Plucks in this showing, and shown so far.
    plucks: i32 = 0;
    plucked: i32 = 0;
    // How far aside the string stood when the pointer took hold, how far it
    // drags it, and how fast it was going as it let go, in points and
    // points a second.
    pullFrom: f64 = 0;
    depth: f64 = 0;
    carry: f64 = 0;
    // Seconds until the next showing, below 0 for none, and its plucks.
    startIn: f64 = FIRST_WAIT;
    startPlucks: i32 = 2;
    missedShown: i32 = 0;
    // True once the first showing has run to its end.
    firstDone: bool = false;

    // The pointer: where its tip is, where its move began, how clearly it
    // shows, and how far it is pressed in.
    tipX: f64 = 0;
    tipY: f64 = 0;
    fromX: f64 = 0;
    fromY: f64 = 0;
    shown: f64 = 0;
    shownGoal: f64 = 0;
    shownFade: f64 = LEAVE;
    press: f64 = 0;
    pressGoal: f64 = 0;
    // How near the coming pointer is to taking hold, 0 to 1, for the mark
    // the string shows there.
    hover: f64 = 0;
    // The rings a click and a let go leave: where, and how long ago, below 0
    // for none.
    downX: f64 = 0;
    downY: f64 = 0;
    downAge: f64 = -1;
    upX: f64 = 0;
    upY: f64 = 0;
    upAge: f64 = -1;

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
    arrow: Path = new Path();
    ring: Path = new Path();
    paint: Paint = new Paint();
    fill: Paint = new Paint();

    constructor() {
        this.paint.style = PaintStyle.stroke;
        this.paint.cap = StrokeCap.round;
        this.paint.join = StrokeJoin.round;
        this.fill.style = PaintStyle.fill;
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
                this.shown = 0;
                this.shownGoal = 0;
                this.press = 0;
                this.pressGoal = 0;
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
            this.lineFade = POINTER_AWAY;
            this.pressGoal = 0;
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

    /// The real pointer moved while up. `near` is whether a press there
    /// would take the waiting string.
    hovering(near: bool): void {
        if (near && !this.near) {
            // Close enough to take it: a pluck being shown steps aside, and
            // the mark the strings draw under the real pointer says the
            // rest. If the visitor does not take it, the pluck is shown
            // again soon, there under the pointer. A showing already owed is
            // kept.
            let showing = this.step == COMING || this.step == PRESSING || this.step == THROWING
                || this.step == FOLLOWING || this.step == WAITING;
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

    /// The real pointer left the scene.
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

    // Stops a pluck under way and sends the pointer away. Holding the
    // string, it gives it back slowly, unless the visitor has just taken it.
    private sendAway(giveBack: bool): void {
        if (this.step == PRESSING || this.step == THROWING) {
            this.step = giveBack ? EASING : RESTING;
        } else if (this.step != EASING) {
            this.step = RESTING;
        }
        this.stepTime = 0;
        this.shownGoal = 0;
        this.shownFade = POINTER_AWAY;
        this.pressGoal = 0;
        this.hover = 0;
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
            this.shownGoal = 0;
            this.shownFade = POINTER_AWAY;
            this.startIn = -1;
        }
        // The pointer comes up and goes, presses in and comes out, and the
        // rings it leaves spread.
        if (this.shownGoal > this.shown) {
            this.shown = Math.min(this.shownGoal, this.shown + dt / POINTER_IN);
        } else {
            this.shown = Math.max(this.shownGoal, this.shown - dt / this.shownFade);
        }
        if (this.pressGoal > this.press) {
            this.press = Math.min(this.pressGoal, this.press + dt / CLICK);
        } else {
            this.press = Math.max(this.pressGoal, this.press - dt / CLICK);
        }
        if (this.downAge >= 0) {
            this.downAge = this.downAge + dt > RING ? -1 : this.downAge + dt;
        }
        if (this.upAge >= 0) {
            this.upAge = this.upAge + dt > RING ? -1 : this.upAge + dt;
        }
        if (line != null) {
            if (!this.rung && this.step == RESTING && !this.pointerDown) {
                if (this.startIn >= 0) {
                    this.startIn -= dt;
                    if (this.startIn <= 0) {
                        this.startIn = -1;
                        this.begin(this.startPlucks, line, strings);
                    }
                } else if (this.idle >= IDLE_WAIT) {
                    this.idle = 0;
                    this.begin(1, line, strings);
                }
            }
            this.movePluck(dt, line, strings);
        }
        this.moveLine(dt, strings);
    }

    // Starts a showing of `plucks` plucks: the pointer appears below and to
    // the right of where it will take hold.
    private begin(plucks: i32, line: StringLine, strings: Strings): void {
        let at = strings.pointOn(line, TAKE_AT);
        this.plucks = plucks;
        this.plucked = 0;
        this.step = COMING;
        this.stepTime = 0;
        this.comeTime = ENTER;
        this.fromX = <f64>at.x + ENTER_X;
        this.fromY = <f64>at.y + ENTER_Y;
        this.tipX = this.fromX;
        this.tipY = this.fromY;
        this.shown = 0;
        this.shownGoal = 1;
        this.press = 0;
        this.pressGoal = 0;
    }

    // Moves a pluck shown on by `dt`, one step at most.
    private movePluck(dt: f64, line: StringLine, strings: Strings): void {
        if (this.step == RESTING) {
            return;
        }
        this.stepTime += dt;
        // Toward the side the string is dragged to.
        let nx = -(line.by - line.ay) / line.length;
        let ny = (line.bx - line.ax) / line.length;
        if (this.step == COMING) {
            if (line.heldPoint >= 0) {
                // Someone else's finger is on it.
                this.sendAway(true);
                return;
            }
            // Along a slight curve, quick to start and slow to arrive, as a
            // hand aims a mouse; to the string where it stands now, so a
            // string still ringing is caught where it is.
            let at = strings.pointOn(line, TAKE_AT);
            let gx = <f64>at.x;
            let gy = <f64>at.y;
            let t = Math.min(this.stepTime / this.comeTime, 1);
            let e = this.comeTime == ENTER ? 1 - (1 - t) * (1 - t) * (1 - t) : smooth(t);
            let mx = 0.5 * (this.fromX + gx) + 0.18 * (gy - this.fromY);
            let my = 0.5 * (this.fromY + gy) - 0.18 * (gx - this.fromX);
            let u = 1 - e;
            this.tipX = u * u * this.fromX + 2 * u * e * mx + e * e * gx;
            this.tipY = u * u * this.fromY + 2 * u * e * my + e * e * gy;
            let dx = this.tipX - gx;
            let dy = this.tipY - gy;
            this.hover = Math.max(0, 1 - Math.sqrt(dx * dx + dy * dy) / REACH);
            if (this.stepTime >= this.comeTime) {
                // The click: it takes hold where the string stands.
                line.hold(TAKE_AT);
                this.pullFrom = line.finger;
                let share = this.plucks >= 2 ? (this.plucked == 0 ? LIGHT : HARD) : ONCE;
                this.depth = share * line.length * PULL_LIMIT;
                this.pressGoal = 1;
                this.downX = gx;
                this.downY = gy;
                this.downAge = 0;
                this.hover = 0;
                this.step = PRESSING;
                this.stepTime = 0;
            }
            return;
        }
        if (this.step == PRESSING || this.step == THROWING) {
            if (line.heldPoint < 0 || strings.held == line) {
                // Taken over, or let go of by something else.
                this.step = RESTING;
                this.shownGoal = 0;
                this.shownFade = POINTER_AWAY;
                this.pressGoal = 0;
                return;
            }
            // Faster and faster, so it lets go at full speed. The pointer
            // leads and the string follows it, as under a real one.
            let u = this.step == THROWING ? Math.min(this.stepTime / THROW, 1) : 0.0;
            line.fingerTarget = this.pullFrom + (this.depth - this.pullFrom) * u * u;
            let along = line.heldAt;
            this.tipX = line.ax + (line.bx - line.ax) * along + nx * line.fingerTarget;
            this.tipY = line.ay + (line.by - line.ay) * along + ny * line.fingerTarget;
            if (this.step == PRESSING && this.stepTime >= PRESS) {
                this.step = THROWING;
                this.stepTime = 0;
            } else if (this.step == THROWING && this.stepTime >= THROW) {
                line.letGo();
                this.plucked++;
                this.carry = 2 * (this.depth - this.pullFrom) / THROW;
                this.pressGoal = 0;
                this.upX = this.tipX;
                this.upY = this.tipY;
                this.upAge = 0;
                this.fromX = this.tipX;
                this.fromY = this.tipY;
                this.step = FOLLOWING;
                this.stepTime = 0;
            }
            return;
        }
        if (this.step == FOLLOWING) {
            let gone = this.carry * CARRY * (1 - Math.exp(-this.stepTime / CARRY));
            this.tipX = this.fromX + nx * gone;
            this.tipY = this.fromY + ny * gone;
            if (this.stepTime >= FOLLOW) {
                this.stepTime = 0;
                this.fromX = this.tipX;
                this.fromY = this.tipY;
                if (this.plucked < this.plucks) {
                    this.step = WAITING;
                } else {
                    this.step = LEAVING;
                    this.shownGoal = 0;
                    this.shownFade = LEAVE;
                }
            }
            return;
        }
        if (this.step == WAITING) {
            if (this.stepTime >= WAIT) {
                this.comeTime = RETURN;
                this.step = COMING;
                this.stepTime = 0;
            }
            return;
        }
        if (this.step == LEAVING) {
            let t = smooth(this.stepTime / LEAVE);
            this.tipX = this.fromX + 10 * t;
            this.tipY = this.fromY + 14 * t;
            if (this.stepTime >= LEAVE) {
                this.step = RESTING;
                this.firstDone = true;
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

    // The pointer clicks at the start and drags to the end.
    private startLine(x0: f64, y0: f64, x1: f64, y1: f64): void {
        this.x0 = x0;
        this.y0 = y0;
        this.x1 = x1;
        this.y1 = y1;
        this.lineStep = DRAWING;
        this.lineTime = 0;
        this.lineShown = 0;
        // Only one pointer is ever seen.
        this.step = RESTING;
        this.shown = 0;
        this.shownGoal = 0;
        this.pressGoal = 1;
        this.downX = x0;
        this.downY = y0;
        this.downAge = 0;
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
            this.lineFade = POINTER_AWAY;
            this.pressGoal = 0;
        }
        this.lineTime += dt;
        if (this.lineStep == DRAWING) {
            this.lineShown = Math.min(1, this.lineShown + dt / POINTER_IN);
            if (this.lineTime >= DRAW) {
                // Let go at the end of the line.
                this.pressGoal = 0;
                this.upX = this.x1;
                this.upY = this.y1;
                this.upAge = 0;
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
        this.drawRing(renderer, this.downX, this.downY, this.downAge, 1.0);
        this.drawRing(renderer, this.upX, this.upY, this.upAge, 0.6);
        if (this.lineStep != NO_LINE && this.lineShown > 0.01) {
            let shown = smooth(this.lineShown);
            let reach = this.lineStep == DRAWING ? smooth(this.lineTime / DRAW) : 1.0;
            let ex = this.x0 + (this.x1 - this.x0) * reach;
            let ey = this.y0 + (this.y1 - this.y0) * reach;
            let path = this.path;
            let paint = this.paint;
            path.reset();
            path.moveTo(Vector.xy(<f32>this.x0, <f32>this.y0));
            path.lineTo(Vector.xy(<f32>ex, <f32>ey));
            paint.thickness = 1.2;
            paint.feather = 0;
            paint.color = Color.rgba(232, 242, 255, <i32>(110 * shown));
            renderer.drawPath(path, paint);
            this.drawPointer(renderer, ex, ey, shown);
            return;
        }
        let shown = smooth(this.shown);
        if (shown <= 0.01) {
            return;
        }
        let line = this.line;
        if (line != null) {
            if (this.step == COMING && this.hover > 0.01) {
                // Where it would take hold, as the string marks it under a
                // real pointer.
                let h = this.hover * shown;
                strings.drawDot(renderer, strings.pointOn(line, TAKE_AT), 2.4 * h,
                    Color.rgba(150, 205, 255, <i32>(110 * h)),
                    Color.rgba(232, 242, 255, <i32>(200 * h)));
            }
            if ((this.step == PRESSING || this.step == THROWING || this.step == EASING)
                && line.heldPoint >= 0) {
                // Under the pointer, the point it holds the string by.
                let heat = inkColor(0.15 + 0.7 * line.tension);
                strings.drawDot(renderer, strings.pointOn(line, line.heldAt), 3 + 1.5 * line.tension,
                    withAlpha(heat, <i32>(150 * shown)),
                    Color.rgba(255, 252, 245, <i32>(255 * shown)));
            }
        }
        this.drawPointer(renderer, this.tipX, this.tipY, shown);
    }

    // The arrow, its tip at (x, y): white with a dark edge as a mouse
    // pointer is, with a faint blue glow so it reads as no one's own, a
    // little smaller while pressed.
    private drawPointer(renderer: Renderer, x: f64, y: f64, alpha: f64): void {
        let size = 1 - PRESSED * smooth(this.press);
        let arrow = this.arrow;
        arrow.reset();
        for (let i = 0; i < ARROW_X.length; i++) {
            let at = Vector.xy(<f32>(x + ARROW_X[i] * size), <f32>(y + ARROW_Y[i] * size));
            if (i == 0) {
                arrow.moveTo(at);
            } else {
                arrow.lineTo(at);
            }
        }
        arrow.close();
        let fill = this.fill;
        fill.feather = 10;
        fill.color = Color.rgba(150, 205, 255, <i32>(80 * alpha));
        renderer.drawPath(arrow, fill);
        fill.feather = 0;
        fill.color = Color.rgba(246, 249, 255, <i32>(240 * alpha));
        renderer.drawPath(arrow, fill);
        let paint = this.paint;
        paint.thickness = 1.1;
        paint.feather = 0;
        paint.color = Color.rgba(6, 9, 15, <i32>(220 * alpha));
        renderer.drawPath(arrow, paint);
    }

    // The ring a click or a let go leaves, spreading and fading.
    private drawRing(renderer: Renderer, x: f64, y: f64, age: f64, strength: f64): void {
        if (age < 0) {
            return;
        }
        let t = Math.min(age / RING, 1);
        let r = 4 + 14 * smooth(t);
        let k = KAPPA * r;
        let ring = this.ring;
        ring.reset();
        ring.moveTo(Vector.xy(<f32>(x + r), <f32>y));
        ring.cubicTo(Vector.xy(<f32>(x + r), <f32>(y + k)), Vector.xy(<f32>(x + k), <f32>(y + r)), Vector.xy(<f32>x, <f32>(y + r)));
        ring.cubicTo(Vector.xy(<f32>(x - k), <f32>(y + r)), Vector.xy(<f32>(x - r), <f32>(y + k)), Vector.xy(<f32>(x - r), <f32>y));
        ring.cubicTo(Vector.xy(<f32>(x - r), <f32>(y - k)), Vector.xy(<f32>(x - k), <f32>(y - r)), Vector.xy(<f32>x, <f32>(y - r)));
        ring.cubicTo(Vector.xy(<f32>(x + k), <f32>(y - r)), Vector.xy(<f32>(x + r), <f32>(y - k)), Vector.xy(<f32>(x + r), <f32>y));
        ring.close();
        let paint = this.paint;
        paint.thickness = 1.5;
        paint.feather = 0;
        paint.color = Color.rgba(220, 235, 255, <i32>(210 * strength * (1 - t)));
        renderer.drawPath(ring, paint);
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
