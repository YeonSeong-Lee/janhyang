import { Tests } from "rive/test";
import { chordMidi, frequencyOf } from "./harmony";
import { Strings, pitchOf } from "./strings";
import { Controls } from "./controls";
import { Phrase } from "./phrase";

export class HarmonyTests extends Tests {
    override run(): void {
        test("every length including the extremes stays inside the chosen chord", (expect) => {
            for (let mood = 0; mood < 3; mood++) {
                for (let length: f64 = 1; length <= 10000; length *= 1.17) {
                    let frequency = pitchOf(length, 720, mood);
                    let midi = <i32>Math.round(69 + 12 * Math.log2(frequency / 440));
                    let allowed = false;
                    for (let degree = 0; degree < 3; degree++) {
                        if (midi % 12 == chordMidi(mood, degree) % 12) allowed = true;
                    }
                    expect.that(allowed).is(true);
                    expect.that(frequency).greaterThanOrEqual(frequencyOf(48) - 0.001);
                    expect.that(frequency).lessThanOrEqual(frequencyOf(81) + 0.001);
                }
                expect.that(pitchOf(720, 720, mood) * 2).is(pitchOf(360, 720, mood));
            }
        });

        test("drawing preview matches the committed string and excludes taps", (expect) => {
            let strings = new Strings();
            strings.height = 720;
            strings.tune(1);
            strings.press(40, 100);
            strings.drag(60, 100);
            expect.that(strings.previewFrequency).is(0);
            strings.drag(240, 100);
            let preview = strings.previewFrequency;
            expect.that(preview).greaterThan(0);
            strings.release(240, 100);
            expect.that(strings.lines[0].frequency).is(preview);
            expect.that(strings.previewFrequency).is(0);
        });

        test("retuning preserves geometry and original pitch intent even after resize", (expect) => {
            let strings = new Strings();
            strings.height = 720;
            let line = strings.add(100, 120, 520, 120);
            let original = line.frequency;
            strings.height = 390;
            for (let i = 0; i < 10; i++) {
                strings.tune(1);
                strings.tune(2);
                strings.tune(0);
            }
            expect.that(line.frequency).is(original);
            expect.that(line.ax).is(100);
            expect.that(line.bx).is(520);
            expect.that(line.ay).is(120);
        });

        test("starter strings make a full triad on a phone and preserve chord roles", (expect) => {
            let strings = new Strings();
            strings.height = 568;
            let controls = new Controls();
            controls.seed(strings, 320, 568);
            controls.seed(strings, 320, 568);
            expect.that(strings.lines.length).is(3);
            for (let mood = 0; mood < 3; mood++) {
                strings.tune(mood);
                for (let i = 0; i < 3; i++) {
                    let line = strings.lines[i];
                    expect.that(line.frequency).is(frequencyOf(chordMidi(mood, i)));
                    expect.that(line.ax).greaterThanOrEqual(24);
                    expect.that(line.bx).lessThanOrEqual(296);
                    expect.that(line.ay).lessThanOrEqual(228);
                }
            }
        });

        test("starter never replaces a drawn string and fits beside landscape controls", (expect) => {
            let strings = new Strings();
            strings.height = 360;
            let controls = new Controls();
            controls.seed(strings, 740, 360);
            expect.that(strings.lines[2].bx).lessThan(372);
            expect.that(strings.lines[1].ay - strings.lines[0].ay).greaterThan(48);
            let other = new Strings();
            other.add(40, 100, 200, 100);
            controls.seed(other, 320, 568);
            expect.that(other.lines.length).is(1);
        });

        test("phrase uses real strings in pitch order, completes and can be cancelled", (expect) => {
            let strings = new Strings();
            strings.height = 720;
            let high = strings.add(0, 100, 200, 100);
            let low = strings.add(0, 200, 700, 200);
            let phrase = new Phrase();
            phrase.start(strings);
            expect.that(phrase.advance(0) == low).is(true);
            expect.that(phrase.advance(0.48) == high).is(true);
            let count = 2;
            for (let i = 0; i < 600; i++) if (phrase.advance(1.0 / 60) != null) count++;
            expect.that(count).is(9);
            expect.that(phrase.playing).is(false);
            phrase.start(strings);
            phrase.stop();
            expect.that(phrase.advance(10) == null).is(true);
            phrase.start(new Strings());
            expect.that(phrase.playing).is(false);
        });

        test("late frames keep the phrase on time without replaying overdue notes", (expect) => {
            let strings = new Strings();
            strings.height = 720;
            let controls = new Controls();
            controls.seed(strings, 1280, 720);
            let phrase = new Phrase();
            phrase.start(strings);
            expect.that(phrase.advance(0) == strings.lines[0]).is(true);
            // At one second, the third note is due. Do not play the late
            // second note and shift every subsequent note by another frame.
            expect.that(phrase.advance(1) == strings.lines[2]).is(true);
            expect.that(phrase.advance(0) == null).is(true);
            for (let i = 0; i < 4; i++) phrase.advance(1);
            expect.that(phrase.playing).is(false);
            // Returning after a long suspension must not restart old notes.
            phrase.start(strings);
            expect.that(phrase.advance(60) == null).is(true);
            expect.that(phrase.playing).is(false);
        });
    }
}
