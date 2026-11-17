import { Tests } from "rive/test";
import { Controls } from "./controls";
import { Guide } from "./guide";
import { Strings, RELEASED_STRING, RELEASED_PLUCK, STRING_STEP } from "./strings";

export class ControlsTests extends Tests {
    override run(): void {
        test("button-created strings fit a narrow viewport and vary in pitch", (expect) => {
            let strings = new Strings();
            strings.height = 568;
            let controls = new Controls();
            let short = controls.create(strings, 320, 568, 0.3);
            let long = controls.create(strings, 320, 568, 0.75);
            expect.that(short.ax).greaterThanOrEqual(16);
            expect.that(long.bx).lessThanOrEqual(304);
            expect.that(short.frequency).greaterThan(long.frequency);
            expect.that(controls.current(strings) == long).is(true);
        });

        test("selection includes pointer strings and skips retired strings", (expect) => {
            let strings = new Strings();
            strings.height = 720;
            strings.press(100, 100);
            strings.release(500, 100);
            let pointer = strings.lines[0];
            let controls = new Controls();
            let button = controls.create(strings, 1280, 720, 0.5);
            controls.select(strings, -1);
            expect.that(controls.current(strings) == pointer).is(true);
            controls.select(strings, -1);
            expect.that(controls.current(strings) == button).is(true);
            pointer.leaving = true;
            controls.select(strings, 1);
            expect.that(controls.current(strings) == button).is(true);
            strings.remove(button);
            expect.that(controls.current(strings) == null).is(true);
            expect.that(controls.pluck(strings, 0.5) == null).is(true);
        });

        test("a discrete pluck starts the real string wave and returns its note", (expect) => {
            let strings = new Strings();
            strings.height = 720;
            let controls = new Controls();
            let line = controls.create(strings, 1280, 720, 0.5);
            let note = controls.pluck(strings, 0.85);
            expect.that(note != null).is(true);
            if (note != null) {
                expect.that(note.frequency).is(line.frequency);
                expect.that(note.strength).is(0.85);
            }
            expect.that(line.heldPoint).is(-1);
            let initial = line.swingAt(0.5);
            expect.that(initial).greaterThan(0);
            for (let i = 0; i < 30; i++) strings.step();
            expect.that(line.swingAt(0.5)).never.is(initial);
        });

        test("a button pluck takes ownership from a running demonstration", (expect) => {
            let strings = new Strings();
            strings.height = 720;
            let controls = new Controls();
            let guide = new Guide();
            guide.resize(1280, 720);
            guide.controlStarted(strings);
            let line = controls.create(strings, 1280, 720, 0.5);
            strings.released = RELEASED_STRING;
            guide.released(strings);
            for (let i = 0; i < 250; i++) {
                guide.advance(1.0 / 60, strings);
                strings.step();
            }
            expect.that(line.heldPoint).greaterThanOrEqual(0);
            guide.controlStarted(strings);
            controls.pluck(strings, 0.5);
            strings.released = RELEASED_PLUCK;
            guide.released(strings);
            guide.advance(STRING_STEP, strings);
            expect.that(guide.rung).is(true);
            expect.that(line.heldPoint).is(-1);
            expect.that(line.fingerTarget).greaterThan(0);
        });
    }
}
