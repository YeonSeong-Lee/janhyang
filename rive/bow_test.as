import { Tests } from "rive/test";
import { Bow } from "./bow";
import { Strings, STRING_STEP } from "./strings";
import { Inputs, Note, Pluck } from "./pluck";

function instrument(): Strings {
    let strings = new Strings();
    strings.height = 720;
    strings.add(100, 200, 650, 200);
    strings.add(100, 280, 500, 280);
    strings.add(100, 600, 650, 600);
    return strings;
}

function energy(samples: StaticArray<f32>): f64 {
    let sum: f64 = 0;
    for (let i = 0; i < samples.length; i++) sum += samples[i] * samples[i];
    return sum / samples.length;
}

function tone(samples: StaticArray<f32>, frequency: f64): f64 {
    let real: f64 = 0;
    let imaginary: f64 = 0;
    for (let i = 0; i < samples.length; i++) {
        let phase = 2 * Math.PI * frequency * <f64>i / 48000;
        real += samples[i] * Math.cos(phase);
        imaginary += samples[i] * Math.sin(phase);
    }
    return Math.sqrt(real * real + imaginary * imaginary) / samples.length;
}

export class BowTests extends Tests {
    override run(): void {
        test("a solo stroke locks one string until release", (expect) => {
            let strings = instrument();
            let bow = new Bow();
            bow.press(300, 205, strings);
            bow.move(300, 280, strings);
            bow.advance(1.0 / 60, strings);
            expect.that(bow.contacts).is(1);
            expect.that(strings.lines[0].bowStrength).greaterThan(0);
            expect.that(strings.lines[1].bowStrength).is(0);
            bow.cancel(strings);
            bow.press(300, 280, strings);
            bow.move(300, 260, strings);
            bow.advance(1.0 / 60, strings);
            expect.that(strings.lines[0].bowStrength).is(0);
            expect.that(strings.lines[1].bowStrength).greaterThan(0);
        });

        test("hover and a stationary press are silent", (expect) => {
            let strings = instrument();
            let bow = new Bow();
            bow.polyphonic = true;
            bow.move(300, 240, strings);
            bow.advance(1.0 / 60, strings);
            expect.that(bow.contacts).is(2);
            expect.that(bow.sounding).is(false);
            bow.press(300, 240, strings);
            bow.advance(1.0 / 60, strings);
            expect.that(bow.sounding).is(false);
            expect.that(strings.lines[0].heldPoint).is(-1);
        });

        test("one stroke sustains every contacted string and leaves distant strings quiet", (expect) => {
            let strings = instrument();
            let bow = new Bow();
            bow.polyphonic = true;
            bow.press(300, 240, strings);
            bow.move(300, 255, strings);
            bow.advance(1.0 / 60, strings);
            expect.that(bow.contacts).is(2);
            expect.that(strings.lines[0].bowStrength).greaterThan(0);
            expect.that(strings.lines[1].bowStrength).greaterThan(0);
            expect.that(strings.lines[2].bowStrength).is(0);
            bow.move(300, 230, strings);
            bow.advance(1.0 / 60, strings);
            expect.that(bow.sounding).is(true);
            expect.that(bow.dx).is(0);
            expect.that(bow.dy).is(1);
            expect.that(strings.lines.length).is(3);
        });

        test("stopping and cancelling do not leave a sustained note", (expect) => {
            let strings = instrument();
            let bow = new Bow();
            bow.polyphonic = true;
            bow.press(300, 240, strings);
            bow.move(300, 260, strings);
            bow.advance(1.0 / 60, strings);
            for (let i = 0; i < 40; i++) bow.advance(1.0 / 60, strings);
            expect.that(bow.sounding).is(false);
            expect.that(strings.lines[0].bowStrength).is(0);
            bow.move(300, 230, strings);
            bow.advance(1.0 / 60, strings);
            expect.that(bow.sounding).is(true);
            bow.cancel(strings);
            expect.that(bow.contacts).is(0);
            expect.that(bow.visible).is(false);
            expect.that(strings.lines[1].bowStrength).is(0);
        });

        test("a fast stroke catches strings between pointer events", (expect) => {
            let strings = instrument();
            let bow = new Bow();
            bow.polyphonic = true;
            bow.press(50, 240, strings);
            bow.move(750, 320, strings);
            bow.advance(1.0 / 60, strings);
            expect.that(bow.contacts).is(0);
            expect.that(strings.lines[0].bowStrength).greaterThan(0);
            expect.that(strings.lines[1].bowStrength).greaterThan(0);
            bow.advance(1.0 / 60, strings);
            expect.that(bow.sounding).is(false);
        });

        test("sliding along a string relocates the bow without sounding it", (expect) => {
            let strings = instrument();
            let bow = new Bow();
            bow.polyphonic = true;
            bow.press(200, 240, strings);
            bow.move(450, 240, strings);
            bow.advance(1.0 / 60, strings);
            expect.that(bow.contacts).is(2);
            expect.that(bow.sounding).is(false);
            expect.that(strings.lines[0].bowAt).is(0.5);
            bow.move(450, 260, strings);
            bow.advance(1.0 / 60, strings);
            expect.that(bow.sounding).is(true);
            expect.that(strings.lines[0].bowAt).greaterThan(0.6);
        });

        test("pressure, speed and reversal respond independently", (expect) => {
            let strings = instrument();
            let bow = new Bow();
            bow.polyphonic = true;
            bow.press(300, 240, strings);
            bow.pressure = 0;
            bow.move(300, 260, strings);
            bow.advance(1.0 / 60, strings);
            expect.that(bow.sounding).is(false);
            bow.pressure = 0.5;
            bow.move(300, 280, strings);
            bow.advance(1.0 / 60, strings);
            expect.that(bow.sounding).is(true);
            expect.that(bow.direction).is(1);
            bow.move(300, 240, strings);
            bow.advance(1.0 / 60, strings);
            expect.that(bow.direction).is(-1);
            expect.that(bow.velocity).lessThan(0);
        });

        test("the bow orients across vertical strings and ignores retired ones", (expect) => {
            let strings = new Strings();
            strings.add(200, 100, 200, 600);
            strings.add(280, 100, 280, 600);
            let bow = new Bow();
            bow.polyphonic = true;
            bow.press(240, 300, strings);
            expect.that(bow.dx).is(-1);
            expect.that(bow.dy).is(0);
            expect.that(bow.contacts).is(2);
            strings.lines[1].leaving = true;
            bow.move(260, 300, strings);
            bow.advance(1.0 / 60, strings);
            expect.that(bow.contacts).is(1);
            expect.that(strings.lines[1].bowStrength).is(0);
        });

        test("continuous bowing keeps the physical strings bounded with fixed anchors", (expect) => {
            let strings = instrument();
            let bow = new Bow();
            bow.polyphonic = true;
            bow.press(300, 240, strings);
            for (let frame = 0; frame < 180; frame++) {
                bow.move(300, 240 + Math.sin(<f64>frame / 12) * 45, strings);
                bow.advance(1.0 / 60, strings);
                for (let step = 0; step < <i32>(1 / (60 * STRING_STEP)); step++) strings.step();
            }
            let line = strings.lines[0];
            let peak: f64 = 0;
            for (let i = 0; i < line.now.length; i++) peak = Math.max(peak, Math.abs(line.now[i]));
            expect.that(peak).greaterThan(0.05);
            expect.that(peak).lessThan(line.length * 0.22);
            expect.that(line.now[0]).is(0);
            expect.that(line.now[line.pieces]).is(0);
        });

        test("two sustained audio voices mix both pitches and expire without a release event", (expect) => {
            let inputs = new Inputs();
            let audio = new Pluck();
            audio.init(48000, 4800, 1, inputs);
            let note = new Note();
            note.voice = 0;
            note.frequency = 220;
            note.gain = 0.5;
            inputs.notes.send(note);
            note.voice = 1;
            note.frequency = 330;
            inputs.notes.send(note);
            let samples = new StaticArray<f32>(4800);
            audio.process(samples, 4800, 0);
            expect.that(tone(samples, 220)).greaterThan(0.006);
            expect.that(tone(samples, 330)).greaterThan(0.006);
            expect.that(tone(samples, 275)).lessThan(0.003);
            for (let block = 0; block < 12; block++) {
                for (let i = 0; i < samples.length; i++) samples[i] = 0;
                audio.process(samples, 4800, <f64>(block + 1) * 4800);
            }
            expect.that(energy(samples)).lessThan(0.00000001);
        });
    }
}
