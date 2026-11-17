import { Color } from "rive/color";
import { Paint, PaintStyle, StrokeCap } from "rive/paint";
import { Path } from "rive/path";
import { Renderer } from "rive/renderer";
import { Vector } from "rive/vector";
import { Strings, StringLine, MAX_KEPT } from "./strings";

/// One visible bow can touch every string along its hair at the same time.
/// Its angle follows the nearest string before a press, then stays fixed
/// throughout that stroke, including when the direction reverses.
export class Bow {
    down: bool = false;
    visible: bool = false;
    x: f64 = 0;
    y: f64 = 0;
    dx: f64 = 0;
    dy: f64 = 1;
    halfLength: f64 = 160;
    travel: f64 = 0;
    speed: f64 = 0;
    contacts: i32 = 0;
    sounding: bool = false;
    along: StaticArray<f64> = new StaticArray<f64>(MAX_KEPT);
    swept: StaticArray<f64> = new StaticArray<f64>(MAX_KEPT);
    path: Path = new Path();
    paint: Paint = new Paint();

    constructor() {
        this.paint.style = PaintStyle.stroke;
        this.paint.cap = StrokeCap.round;
        this.clearContacts();
    }

    private clearContacts(): void {
        for (let i = 0; i < MAX_KEPT; i++) {
            this.along[i] = -1;
            this.swept[i] = -1;
        }
        this.contacts = 0;
    }

    resize(width: f64, height: f64): void {
        this.halfLength = Math.max(70, Math.min(190, Math.min(width, height) * 0.32));
    }

    move(x: f64, y: f64, strings: Strings): void {
        let fromX = this.x;
        let fromY = this.y;
        let distance = Math.sqrt((x - fromX) * (x - fromX) + (y - fromY) * (y - fromY));
        this.visible = true;
        if (!this.down) {
            let nearest = strings.nearestTo(x, y);
            if (nearest != null) {
                this.dx = -(nearest.by - nearest.ay) / nearest.length;
                this.dy = (nearest.bx - nearest.ax) / nearest.length;
            }
        } else {
            this.travel += distance;
            // Check the swept path, so a quick stroke cannot tunnel through
            // strings between two input events. Bound the work after a jump.
            let steps = <i32>Math.max(1, Math.min(96, Math.ceil(distance / 8)));
            for (let step = 1; step <= steps; step++) {
                this.x = fromX + (x - fromX) * <f64>step / steps;
                this.y = fromY + (y - fromY) * <f64>step / steps;
                this.findContacts(strings, true);
            }
        }
        this.x = x;
        this.y = y;
        this.findContacts(strings, false);
    }

    press(x: f64, y: f64, strings: Strings): void {
        this.cancel(strings);
        this.move(x, y, strings);
        this.down = true;
    }

    cancel(strings: Strings): void {
        this.down = false;
        this.visible = false;
        this.travel = 0;
        this.speed = 0;
        this.sounding = false;
        this.clearContacts();
        for (let i = 0; i < strings.lines.length; i++) strings.lines[i].bowStrength = 0;
    }

    /// Intersection with the actual vibrating polyline, excluding its anchors.
    private contact(line: StringLine): f64 {
        let ax = this.x - this.dx * this.halfLength;
        let ay = this.y - this.dy * this.halfLength;
        let ux = this.dx * this.halfLength * 2;
        let uy = this.dy * this.halfLength * 2;
        let nx = -(line.by - line.ay) / line.length;
        let ny = (line.bx - line.ax) / line.length;
        let lastX = line.ax;
        let lastY = line.ay;
        for (let i = 1; i <= line.pieces; i++) {
            let t = <f64>i / line.pieces;
            let px = line.ax + (line.bx - line.ax) * t + nx * line.now[i];
            let py = line.ay + (line.by - line.ay) * t + ny * line.now[i];
            let vx = px - lastX;
            let vy = py - lastY;
            let cross = ux * vy - uy * vx;
            if (Math.abs(cross) > 0.0001) {
                let qx = lastX - ax;
                let qy = lastY - ay;
                let onBow = (qx * vy - qy * vx) / cross;
                let onPiece = (qx * uy - qy * ux) / cross;
                let along = (<f64>(i - 1) + onPiece) / line.pieces;
                if (onBow >= 0 && onBow <= 1 && onPiece >= 0 && onPiece <= 1
                    && along >= 0.04 && along <= 0.96) return along;
            }
            lastX = px;
            lastY = py;
        }
        return -1;
    }

    private findContacts(strings: Strings, sweep: bool): void {
        if (!sweep) this.contacts = 0;
        let voice = 0;
        for (let i = 0; i < strings.lines.length && voice < MAX_KEPT; i++) {
            let line = strings.lines[i];
            if (line.leaving) continue;
            let along = this.contact(line);
            if (sweep) {
                if (along >= 0) this.swept[voice] = along;
            } else {
                this.along[voice] = along;
                if (along >= 0) this.contacts++;
            }
            voice++;
        }
    }

    advance(seconds: f64, strings: Strings): void {
        if (!(seconds > 0)) return;
        let dt = Math.min(seconds, 0.1);
        let target = this.down ? Math.min(this.travel / dt, 1200) : 0;
        this.travel = 0;
        // Quick attack, gentle release; a stationary bow soon falls silent.
        this.speed += (target - this.speed) * (1 - Math.exp(-dt / (target > this.speed ? 0.025 : 0.045)));
        let strength = this.down ? Math.min(this.speed / 420, 1) : 0;
        if (strength < 0.015) strength = 0;
        this.sounding = false;
        if (this.visible) this.findContacts(strings, false);
        let voice = 0;
        for (let i = 0; i < strings.lines.length; i++) {
            let line = strings.lines[i];
            line.bowStrength = 0;
            if (line.leaving || voice >= MAX_KEPT) continue;
            let along = this.along[voice] >= 0 ? this.along[voice] : this.swept[voice];
            if (along >= 0 && strength > 0) {
                line.bowAt = along;
                line.bowStrength = strength;
                this.sounding = true;
            }
            this.swept[voice] = -1;
            voice++;
        }
    }

    private stroke(renderer: Renderer, offset: f64, width: f32, color: Color): void {
        let nx = -this.dy * offset;
        let ny = this.dx * offset;
        this.path.reset();
        this.path.moveTo(Vector.xy(<f32>(this.x - this.dx * this.halfLength + nx),
            <f32>(this.y - this.dy * this.halfLength + ny)));
        this.path.lineTo(Vector.xy(<f32>(this.x + this.dx * this.halfLength + nx),
            <f32>(this.y + this.dy * this.halfLength + ny)));
        this.paint.thickness = width;
        this.paint.feather = 0;
        this.paint.color = color;
        renderer.drawPath(this.path, this.paint);
    }

    draw(renderer: Renderer, strings: Strings): void {
        if (!this.visible) return;
        let alpha = this.down ? 245 : 155;
        this.stroke(renderer, 7, 3, Color.rgba(192, 151, 105, alpha));
        this.stroke(renderer, 0, 1.8, Color.rgba(250, 239, 214, alpha));
        let voice = 0;
        for (let i = 0; i < strings.lines.length && voice < MAX_KEPT; i++) {
            let line = strings.lines[i];
            if (line.leaving) continue;
            let along = this.along[voice++];
            if (along < 0) continue;
            let at = strings.pointOn(line, along);
            strings.drawDot(renderer, at, 3 + 2 * line.bowStrength,
                Color.rgba(255, 188, 95, alpha / 2), Color.rgba(255, 246, 222, alpha));
        }
        strings.drawGrip(renderer, Vector.xy(<f32>this.x, <f32>this.y), this.down ? 6 : 10, 1);
    }
}
