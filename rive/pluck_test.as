import { Tests } from "rive/test";
import { Inputs, Note, Pluck } from "./pluck";

export class PluckTests extends Tests {
    override run(): void {
        test("audio preserves microtones and frequencies outside the old 55-2000 Hz limits", (expect) => {
            let inputs = new Inputs();
            let pluck = new Pluck();
            pluck.init(48000, 128, 1, inputs);
            let frequencies: StaticArray<f32> = [600.25, 600.75, 39.6, 3960.25];
            for (let i = 0; i < frequencies.length; i++) {
                let note = new Note();
                note.frequency = frequencies[i];
                note.gain = 0.5;
                inputs.notes.send(note);
            }
            let samples = new StaticArray<f32>(128);
            pluck.process(samples, 128, 0);
            for (let i = 0; i < frequencies.length; i++) {
                let actual = pluck.rate / (pluck.delays[i] + 0.5);
                expect.that(Math.abs(actual - frequencies[i])).lessThan(0.01);
            }
            let peak: f32 = 0;
            for (let i = 0; i < samples.length; i++) {
                expect.that(isFinite(samples[i])).is(true);
                peak = Mathf.max(peak, Mathf.abs(samples[i]));
            }
            expect.that(peak).greaterThan(0);
        });
    }
}
