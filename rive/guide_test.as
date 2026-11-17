import { Tests } from "rive/test";
import { Guide } from "./guide";
import { Strings, RELEASED_PLUCK, STRING_STEP } from "./strings";

// Exercise the same input order and string simulation as Main, without a GPU.
@editTime
class Visit {
    guide: Guide = new Guide();
    strings: Strings = new Strings();

    constructor() {
        this.resize(1280, 720);
    }

    resize(width: f64, height: f64): void {
        this.strings.height = height;
        this.guide.resize(width, height);
    }

    wait(seconds: f64): void {
        for (let i = 0; i < <i32>Math.ceil(seconds * 60); i++) {
            this.strings.advance(1.0 / 60);
            this.guide.advance(1.0 / 60, this.strings);
            for (let s = 0; s < <i32>Math.round(1.0 / (60 * STRING_STEP)); s++) {
                this.strings.step();
            }
        }
    }

    down(x: f64, y: f64): void {
        this.strings.press(x, y);
        this.guide.pressed(this.strings);
    }

    up(x: f64, y: f64): void {
        this.strings.release(x, y);
        this.strings.unhover();
        this.guide.released(this.strings);
    }

    draw(): void {
        this.down(400, 300);
        this.strings.drag(800, 300);
        this.up(800, 300);
    }
}

export class GuideTests extends Tests {
    override run(): void {
        test("starts empty and shows only a temporary drawing hint", (expect) => {
            let visit = new Visit();
            visit.wait(0.8);
            expect.that(visit.strings.lines.length).is(0);
            expect.that(visit.guide.lineShown).is(0);
            visit.wait(0.5);
            expect.that(visit.guide.lineShown).greaterThan(0);
            expect.that(visit.strings.lines.length).is(0);
            visit.wait(2);
            expect.that(visit.guide.lineShown).is(0);
            visit.wait(60);
            expect.that(visit.strings.lines.length).is(0);
            expect.that(visit.guide.idleLines).is(2);
            expect.that(visit.guide.lineShown).is(0);
        });

        test("a tap before drawing shows a nearby drawing hint", (expect) => {
            let visit = new Visit();
            visit.down(120, 180);
            visit.up(120, 180);
            visit.wait(0.2);
            expect.that(visit.guide.x0).is(120);
            expect.that(visit.guide.y0).is(180);
            expect.that(visit.guide.lineShown).greaterThan(0);
            expect.that(visit.strings.lines.length).is(0);
            expect.that(visit.guide.line == null).is(true);
        });

        test("drawing interrupts the hint without finishing its ghost stroke", (expect) => {
            let visit = new Visit();
            visit.wait(1.3);
            let progress = visit.guide.lineProgress;
            expect.that(progress).greaterThan(0);
            expect.that(progress).lessThan(1);
            visit.down(400, 300);
            visit.wait(0.1);
            expect.that(visit.guide.lineProgress).is(progress);
            visit.wait(4);
            expect.that(visit.guide.lineShown).is(0);
            expect.that(visit.guide.shown).is(0);
            expect.that(visit.strings.drawing).is(true);
            visit.up(800, 300);
            expect.that(visit.strings.lines.length).is(1);
            expect.that(visit.guide.drawn).is(true);
        });

        test("an early drawing skips the intro and gets one pluck after a pause", (expect) => {
            let visit = new Visit();
            visit.draw();
            let line = visit.strings.lines[0];
            visit.wait(2.5);
            expect.that(visit.guide.lineShown).is(0);
            expect.that(visit.guide.shown).is(0);
            expect.that(line.heldPoint).is(-1);
            visit.wait(1.6);
            expect.that(visit.guide.line == line).is(true);
            expect.that(line.heldPoint).greaterThanOrEqual(0);
            visit.wait(2);
            expect.that(line.heldPoint).is(-1);
            expect.that(visit.guide.shown).is(0);
            expect.that(visit.guide.rung).is(false);
            expect.that(visit.strings.lines.length).is(1);
        });

        test("leaving during the first drag restores the drawing hint", (expect) => {
            let visit = new Visit();
            visit.down(100, 100);
            visit.strings.drag(300, 100);
            visit.strings.cancel();
            visit.guide.left();
            visit.wait(3.3);
            expect.that(visit.guide.lineShown).greaterThan(0);
            expect.that(visit.strings.lines.length).is(0);
        });

        test("a successful user pluck ends every hint", (expect) => {
            let visit = new Visit();
            visit.draw();
            visit.down(600, 300);
            visit.strings.drag(600, 350);
            visit.wait(0.2);
            visit.up(600, 350);
            expect.that(visit.strings.released).is(RELEASED_PLUCK);
            expect.that(visit.guide.rung).is(true);
            visit.wait(25);
            expect.that(visit.guide.shown).is(0);
            expect.that(visit.guide.lineShown).is(0);
            visit.down(100, 100);
            visit.up(100, 100);
            visit.wait(4);
            expect.that(visit.guide.shown).is(0);
            expect.that(visit.guide.lineShown).is(0);
        });

        test("the user can take a string directly from the pluck demonstration", (expect) => {
            let visit = new Visit();
            visit.draw();
            visit.wait(4.2);
            let line = visit.strings.lines[0];
            expect.that(line.heldPoint).greaterThanOrEqual(0);
            let point = visit.strings.pointOn(line, line.heldAt);
            visit.down(point.x, point.y);
            visit.strings.drag(point.x, point.y + 50);
            let target = line.fingerTarget;
            visit.wait(0.3);
            expect.that(visit.strings.held == line).is(true);
            expect.that(line.fingerTarget).is(target);
            expect.that(visit.guide.shown).is(0);
            visit.up(point.x, point.y + 50);
            expect.that(visit.guide.rung).is(true);
        });

        test("drawing elsewhere releases the demonstration's hold", (expect) => {
            let visit = new Visit();
            visit.draw();
            visit.wait(4.2);
            let line = visit.strings.lines[0];
            visit.down(100, 100);
            visit.wait(1);
            expect.that(line.heldPoint).is(-1);
            expect.that(visit.strings.drawing).is(true);
            expect.that(visit.guide.shown).is(0);
            visit.up(300, 100);
            expect.that(visit.strings.lines.length).is(2);
        });

        test("resizing repositions the hint but preserves user strings", (expect) => {
            let visit = new Visit();
            visit.wait(1.3);
            visit.resize(390, 844);
            visit.wait(1.3);
            expect.that((visit.guide.x0 + visit.guide.x1) / 2).is(195);
            expect.that((visit.guide.y0 + visit.guide.y1) / 2).is(422);
            visit.down(50, 200);
            visit.up(330, 200);
            let line = visit.strings.lines[0];
            visit.resize(844, 390);
            expect.that(visit.strings.lines.length).is(1);
            expect.that(visit.guide.line == line).is(true);
            expect.that(line.ax).is(50);
            expect.that(line.bx).is(330);
            expect.that(line.ay).is(200);
            expect.that(line.by).is(200);
        });

        test("a retired hint target is replaced with a kept user string", (expect) => {
            let visit = new Visit();
            visit.draw();
            let first = visit.strings.lines[0];
            for (let i = 0; i < 12; i++) {
                visit.down(100, 40 + i * 50);
                visit.up(250, 40 + i * 50);
                visit.wait(0.05);
            }
            visit.wait(4.1);
            expect.that(first.leaving).is(true);
            let target = visit.guide.line;
            expect.that(target != null).is(true);
            if (target != null) {
                expect.that(visit.strings.keeps(target)).is(true);
                expect.that(target.heldPoint).greaterThanOrEqual(0);
            }
        });
    }
}
