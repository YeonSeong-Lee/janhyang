import { Tests } from "rive/test";
import { BowedVoice } from "./bowed";

function render(frequency: f32, speed: f32, pressure: f32, position: f32, rate: f32 = 48000): StaticArray<f32> {
    let bow = new BowedVoice();
    bow.init(rate);
    let samples = new StaticArray<f32>(<i32>(rate * 0.5));
    for (let i = 0; i < samples.length; i++) {
        if (i % 512 == 0) bow.update(frequency, 0.7, speed, pressure, position);
        samples[i] = bow.tick();
    }
    return samples;
}

function power(samples: StaticArray<f32>): f64 {
    let sum: f64 = 0;
    for (let i = samples.length / 2; i < samples.length; i++) sum += <f64>samples[i] * samples[i];
    return sum * 2 / samples.length;
}

export class BowedTests extends Tests {
    override run(): void {
        test("a bow needs motion and pressure to excite a silent string", (expect) => {
            expect.that(power(render(440, 0, 0.5, 0.4))).is(0);
            expect.that(power(render(440, 0.6, 0, 0.4))).is(0);
            expect.that(power(render(440, 0.6, 0.5, 0.4))).greaterThan(0.00005);
        });
        test("both stroke directions sustain comparable energy", (expect) => {
            let forward = power(render(220, 0.6, 0.5, 0.4));
            let backward = power(render(220, -0.6, 0.5, 0.4));
            expect.that(forward).greaterThan(0.00005);
            expect.that(Math.abs(forward - backward)).lessThan(forward * 0.01);
        });
        test("speed controls energy and pressure and contact change the waveform", (expect) => {
            let slow = render(330, 0.25, 0.5, 0.4);
            let fast = render(330, 0.8, 0.5, 0.4);
            expect.that(power(fast)).greaterThan(power(slow) * 1.5);
            let light = render(330, 0.8, 0.2, 0.4);
            let nearEnd = render(330, 0.8, 0.5, 0.08);
            let pressureDifference: f64 = 0;
            let contactDifference: f64 = 0;
            for (let i = 12000; i < 24000; i++) {
                pressureDifference += Math.abs(fast[i] - light[i]);
                contactDifference += Math.abs(fast[i] - nearEnd[i]);
            }
            expect.that(pressureDifference / 12000).greaterThan(0.001);
            expect.that(contactDifference / 12000).greaterThan(0.001);
        });
        test("extreme controls remain finite and bounded at common sample rates", (expect) => {
            let rates: StaticArray<f32> = [44100, 48000, 96000];
            let pitches: StaticArray<f32> = [65, 440, 1320];
            for (let r = 0; r < rates.length; r++) {
                for (let p = 0; p < pitches.length; p++) {
                    let samples = render(pitches[p], 1, 1, 0.04, rates[r]);
                    let valid = true;
                    for (let i = 0; i < samples.length; i++) {
                        if (!(samples[i] >= -1 && samples[i] <= 1)) valid = false;
                    }
                    expect.that(valid).is(true);
                }
            }
        });
        test("lost updates and explicit release both decay to silence", (expect) => {
            for (let explicit = 0; explicit < 2; explicit++) {
                let bow = new BowedVoice();
                bow.init(48000);
                for (let i = 0; i < 24000; i++) {
                    if (i % 512 == 0) bow.update(440, 0.8, 0.6, 0.5, 0.4);
                    bow.tick();
                }
                if (explicit == 1) bow.update(440, 0, 0, 0.5, 0.4);
                let tail: f64 = 0;
                for (let i = 0; i < 48000; i++) {
                    let sample = bow.tick();
                    if (i > 40000) tail += <f64>sample * sample;
                }
                expect.that(tail).lessThan(0.00000001);
                expect.that(bow.active).is(false);
            }
        });
    }
}
