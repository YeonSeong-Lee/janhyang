import { Tests } from "rive/test";
import { Performance } from "./performance";

export class PerformanceTests extends Tests {
    override run(): void {
        test("only the owner can commit a continuous-pitch stroke", (expect) => {
            let performance = new Performance();
            performance.resize(1280, 720);
            expect.that(performance.press(1, 40, 100)).is(true);
            expect.that(performance.press(2, 50, 200)).is(false);
            performance.move(1, 399, 100);
            let preview = performance.strings.previewFrequency;
            expect.that(performance.release(2, 400, 200).accepted).is(false);
            expect.that(performance.strings.drawing).is(true);
            expect.that(performance.release(1, 399, 100).accepted).is(true);
            expect.that(performance.count).is(1);
            expect.that(performance.selectedIndex).is(1);
            expect.that(performance.frequency).is(preview);
            expect.that(preview).greaterThan(440);
            expect.that(performance.notesPlayed).is(0);
        });

        test("cancellation prevents a late release from creating or sounding a string", (expect) => {
            let performance = new Performance();
            performance.resize(1280, 720);
            performance.press(1, 100, 100);
            performance.move(1, 500, 100);
            performance.cancel();
            expect.that(performance.release(1, 500, 100).accepted).is(false);
            expect.that(performance.count).is(0);
            performance.createString(0.5);
            let line = performance.strings.lines[0];
            performance.press(2, (line.ax + line.bx) / 2, line.ay);
            performance.move(2, (line.ax + line.bx) / 2, line.ay + 50);
            performance.cancel();
            expect.that(performance.release(2, line.ax, line.ay).note == null).is(true);
            expect.that(performance.notesPlayed).is(0);
            expect.that(line.heldPoint).is(-1);
        });

        test("a tap reports water feedback without creating a note or string", (expect) => {
            let performance = new Performance();
            performance.resize(1280, 720);
            performance.press(1, 120, 180);
            let result = performance.release(1, 125, 180);
            expect.that(result.tapped).is(true);
            expect.that(result.x).is(120);
            expect.that(result.y).is(180);
            expect.that(result.note == null).is(true);
            expect.that(performance.count).is(0);
            expect.that(performance.notesPlayed).is(0);
        });

        test("buttons take over a draft and phrase playback without a late commit", (expect) => {
            let performance = new Performance();
            performance.resize(1280, 720);
            performance.press(1, 40, 100);
            performance.move(1, 200, 100);
            performance.harmonyStrings(0);
            expect.that(performance.release(1, 200, 100).accepted).is(false);
            expect.that(performance.count).is(3);
            expect.that(performance.playPhrase()).is(true);
            expect.that(performance.advance(0) != null).is(true);
            expect.that(performance.notesPlayed).is(1);
            performance.selectString(1);
            expect.that(performance.demoPlaying).is(false);
            expect.that(performance.advance(1) == null).is(true);
            expect.that(performance.pluckString(0.5) != null).is(true);
            expect.that(performance.notesPlayed).is(2);
        });

        test("phrase toggling and delayed completion use the production interaction path", (expect) => {
            let performance = new Performance();
            performance.resize(1280, 720);
            performance.harmonyStrings(1);
            expect.that(performance.playPhrase()).is(true);
            expect.that(performance.playPhrase()).is(false);
            expect.that(performance.advance(1) == null).is(true);
            performance.playPhrase();
            expect.that(performance.advance(0) != null).is(true);
            expect.that(performance.advance(60) == null).is(true);
            expect.that(performance.demoPlaying).is(false);
            expect.that(performance.notesPlayed).is(1);
        });
    }
}
