// The guide: what a first visitor is shown before they know what to do.
// The water starts empty. A mouse pointer no one holds briefly draws a
// line, leaving no real string behind. Once the visitor draws a string,
// they get a moment to try it before the pointer shows how to pull it and
// let go. A press anywhere sends the pointer away. The guide never makes
// a sound, and retires once the visitor has made their first string ring.
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
// The pointer comes to the visitor's string from aside.
const COMING: i32 = 1;
// It clicks, taking hold of the string, and grips it a moment.
const PRESSING: i32 = 2;
// It drags the string aside, faster and faster, and lets go on the move.
const THROWING: i32 = 3;
// Let go, it carries on a little the way it was going.
const FOLLOWING: i32 = 4;
// The showing over, it fades away.
const LEAVING: i32 = 5;
// Cut short while holding, it gives the string back slowly.
const EASING: i32 = 6;

// The steps of a line shown.
const NO_LINE: i32 = 0;
const DRAWING: i32 = 1;
const SHOWING: i32 = 2;
const FADING: i32 = 3;

// Seconds of empty water before the first drawing hint.
const FIRST_WAIT: f64 = 1.0;
// Seconds each step of a pluck takes: coming in from aside, gripping,
// dragging until let go, carrying on, and fading away.
const ENTER: f64 = 0.9;
const PRESS: f64 = 0.18;
const THROW: f64 = 0.55;
const FOLLOW: f64 = 0.35;
const LEAVE: f64 = 0.5;
// Seconds to try a newly drawn string, or try again after a missed press,
// before a pluck is shown; and the wait between idle reminders.
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
// fraction of the furthest a string can be pulled.
const TAKE_AT: f64 = 0.42;
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
// How much the drawing hint leans, in radians.
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
    /// A string drawn by the visitor, used for the pluck hint while kept.
    line: StringLine? = null;
    width: f64 = 0;
    height: f64 = 0;
    // Set once the visitor has rung a string, and once they have drawn one.
    rung: bool = false;
    drawn: bool = false;
    // Seconds since the last press or release.
    idle: f64 = 0;
    pointerDown: bool = false;
    // The real pointer, up, is within reach of the visitor's string.
    near: bool = false;

    // The pluck shown.
    step: i32 = RESTING;
    stepTime: f64 = 0;
    // How far aside the string stood when the pointer took hold, how far it
    // drags it, and how fast it was going as it let go, in points and
    // points a second.
    pullFrom: f64 = 0;
    depth: f64 = 0;
    carry: f64 = 0;
    // Seconds until the next pluck hint, below 0 for none.
    startIn: f64 = -1;
    missedShown: i32 = 0;

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
    // Keep the partial stroke in place when an input interrupts its fade.
    lineProgress: f64 = 0;
    lineShown: f64 = 0;
    lineFade: f64 = LINE_OUT;
    x0: f64 = 0;
    y0: f64 = 0;
    x1: f64 = 0;
    y1: f64 = 0;
    lineStartIn: f64 = FIRST_WAIT;
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

    /// Only the drawing hint follows the viewport. User strings stay put.
    resize(width: f64, height: f64): void {
        if (width <= 0 || height <= 0) {
            return;
        }
        let changed = Math.abs(width - this.width) >= 1 || Math.abs(height - this.height) >= 1;
        this.width = width;
        this.height = height;
        if (changed && !this.drawn && this.lineStep != NO_LINE) {
            this.lineStep = NO_LINE;
            this.lineShown = 0;
            this.pressGoal = 0;
            this.downAge = -1;
            this.upAge = -1;
            this.lineStartIn = FIRST_WAIT;
        }
    }

    /// A press came down. Call it after Strings.press.
    pressed(strings: Strings): void {
        this.pointerDown = true;
        this.near = false;
        this.idle = 0;
        this.lineStartIn = -1;
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

    /// A discrete control takes over immediately, including while the
    /// demonstration is easing its hold away from an interrupted gesture.
    controlStarted(strings: Strings): void {
        this.pressed(strings);
        if (this.step == EASING) {
            let line = this.line;
            if (line != null && strings.held != line) line.letGo();
            this.step = RESTING;
        }
    }

    /// The press came up. Call it after Strings.release.
    released(strings: Strings): void {
        this.pointerDown = false;
        this.idle = 0;
        let what = strings.released;
        if (what == RELEASED_PLUCK) {
            this.rung = true;
            this.startIn = -1;
            return;
        }
        if (what == RELEASED_STRING) {
            this.drawn = true;
            this.lineStartIn = -1;
            // The release just appended this string. Keep the original
            // target until it retires, even if the visitor draws more.
            if (this.line == null) {
                this.line = strings.lines[strings.lines.length - 1];
            }
            if (!this.rung) {
                this.startIn = MISSED_WAIT;
            }
            return;
        }
        if (!this.drawn && what == RELEASED_TAP) {
            this.showLineFrom(strings.tapX, strings.tapY);
        } else if (!this.rung) {
            this.missed();
        }
    }

    /// The real pointer moved while up. `near` is whether a press there
    /// would take the string used for the hint.
    hovering(near: bool): void {
        if (near && !this.near) {
            // Close enough to take it: a pluck being shown steps aside, and
            // the mark the strings draw under the real pointer says the
            // rest. If the visitor does not take it, the pluck is shown
            // again soon, there under the pointer. A showing already owed is
            // kept.
            let showing = this.step == COMING || this.step == PRESSING || this.step == THROWING
                || this.step == FOLLOWING;
            if (showing) {
                this.sendAway(true);
                if (!this.rung && this.startIn < 0) {
                    this.startIn = MISSED_WAIT;
                }
            }
        }
        this.near = near;
    }

    /// The real pointer left the scene.
    left(): void {
        if (this.pointerDown) {
            this.idle = 0;
            if (!this.drawn) {
                this.lineStartIn = MISSED_WAIT;
            } else if (!this.rung) {
                this.missed();
            }
        }
        this.pointerDown = false;
        this.near = false;
    }

    // A press that rang nothing: the pluck is shown again soon.
    private missed(): void {
        if (this.missedShown < MOST_MISSED && this.line != null) {
            this.missedShown++;
            this.startIn = MISSED_WAIT;
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
            if (line.heldPoint >= 0 && strings.held != line) {
                line.letGo();
            }
            this.line = null;
            line = null;
            this.step = RESTING;
            this.shownGoal = 0;
            this.shownFade = POINTER_AWAY;
            this.pressGoal = 0;
            this.startIn = -1;
        }
        if (line == null && this.drawn && !this.rung) {
            for (let i = strings.lines.length - 1; i >= 0; i--) {
                let candidate = strings.lines[i];
                if (!candidate.leaving) {
                    this.line = candidate;
                    line = candidate;
                    this.startIn = MISSED_WAIT;
                    break;
                }
            }
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
            if (!this.rung && this.step == RESTING && !this.pointerDown && this.lineStep == NO_LINE) {
                if (this.startIn >= 0) {
                    this.startIn -= dt;
                    if (this.startIn <= 0) {
                        this.startIn = -1;
                        this.begin(line, strings);
                    }
                } else if (this.idle >= IDLE_WAIT) {
                    this.idle = 0;
                    this.begin(line, strings);
                }
            }
            this.movePluck(dt, line, strings);
        }
        this.moveLine(dt);
    }

    // Shows one pluck, keeping the arriving pointer inside the viewport.
    private begin(line: StringLine, strings: Strings): void {
        let at = strings.pointOn(line, TAKE_AT);
        this.step = COMING;
        this.stepTime = 0;
        this.fromX = Math.min(Math.max(<f64>at.x + ENTER_X, MARGIN), this.width - MARGIN);
        this.fromY = Math.min(Math.max(<f64>at.y + ENTER_Y, MARGIN), this.height - MARGIN);
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
            let t = Math.min(this.stepTime / ENTER, 1);
            let e = 1 - (1 - t) * (1 - t) * (1 - t);
            let mx = 0.5 * (this.fromX + gx) + 0.18 * (gy - this.fromY);
            let my = 0.5 * (this.fromY + gy) - 0.18 * (gx - this.fromX);
            let u = 1 - e;
            this.tipX = u * u * this.fromX + 2 * u * e * mx + e * e * gx;
            this.tipY = u * u * this.fromY + 2 * u * e * my + e * e * gy;
            let dx = this.tipX - gx;
            let dy = this.tipY - gy;
            this.hover = Math.max(0, 1 - Math.sqrt(dx * dx + dy * dy) / REACH);
            if (this.stepTime >= ENTER) {
                // The click: it takes hold where the string stands.
                line.hold(TAKE_AT);
                this.pullFrom = line.finger;
                // A user string may have either direction and sit by an
                // edge. Pull toward the roomier side, within the viewport.
                let toward = (0.5 * this.width - gx) * nx + (0.5 * this.height - gy) * ny;
                let side = toward < 0 ? -1.0 : 1.0;
                let dx = side * nx;
                let dy = side * ny;
                let room = Infinity;
                if (Math.abs(dx) > 0.001) {
                    room = Math.min(room, ((dx > 0 ? this.width - MARGIN : MARGIN) - gx) / dx);
                }
                if (Math.abs(dy) > 0.001) {
                    room = Math.min(room, ((dy > 0 ? this.height - MARGIN : MARGIN) - gy) / dy);
                }
                this.depth = side * Math.min(ONCE * line.length * PULL_LIMIT, Math.max(room, 0));
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
                this.step = LEAVING;
                this.shownGoal = 0;
                this.shownFade = LEAVE;
            }
            return;
        }
        if (this.step == LEAVING) {
            let t = smooth(this.stepTime / LEAVE);
            this.tipX = this.fromX + 10 * t;
            this.tipY = this.fromY + 14 * t;
            if (this.stepTime >= LEAVE) {
                this.step = RESTING;
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
        x = Math.min(Math.max(x, MARGIN), this.width - MARGIN);
        y = Math.min(Math.max(y, MARGIN), this.height - MARGIN);
        let length = Math.min(LINE_LENGTH, 0.35 * Math.min(this.width, this.height));
        let toward = x < 0.5 * this.width ? 1.0 : -1.0;
        let x1 = x + toward * length * Math.cos(LEAN);
        let y1 = y + length * Math.sin(LEAN);
        this.startLine(x, y,
            Math.min(Math.max(x1, MARGIN), this.width - MARGIN),
            Math.min(Math.max(y1, MARGIN), this.height - MARGIN));
    }

    // Before any real string exists, show the drawing hint in the middle.
    private showLineInMiddle(): void {
        let half = 0.5 * Math.min(LINE_LENGTH, 0.35 * Math.min(this.width, this.height));
        let dx = half * Math.cos(LEAN);
        let dy = half * Math.sin(LEAN);
        let cx = 0.5 * this.width;
        let cy = 0.5 * this.height;
        this.startLine(cx - dx, cy - dy, cx + dx, cy + dy);
    }

    // The pointer clicks at the start and drags to the end.
    private startLine(x0: f64, y0: f64, x1: f64, y1: f64): void {
        this.x0 = x0;
        this.y0 = y0;
        this.x1 = x1;
        this.y1 = y1;
        this.lineStep = DRAWING;
        this.lineTime = 0;
        this.lineProgress = 0;
        this.lineShown = 0;
        this.lineStartIn = -1;
        this.idle = 0;
        // Only one pointer is ever seen.
        this.step = RESTING;
        this.shown = 0;
        this.shownGoal = 0;
        this.pressGoal = 1;
        this.downX = x0;
        this.downY = y0;
        this.downAge = 0;
    }

    // Draw first, then wait for the visitor; idle reminders are bounded.
    private moveLine(dt: f64): void {
        if (!this.drawn && this.width > 0 && this.height > 0
            && this.lineStep == NO_LINE && !this.pointerDown) {
            if (this.lineStartIn >= 0) {
                this.lineStartIn -= dt;
                if (this.lineStartIn <= 0) {
                    this.showLineInMiddle();
                }
            } else if (this.idle >= IDLE_WAIT && this.idleLines < MOST_IDLE_LINES) {
                this.idleLines++;
                this.showLineInMiddle();
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
            this.lineProgress = smooth(this.lineTime / DRAW);
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
            let reach = this.lineProgress;
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
