// The sound of the strings, made inside the file: each note is a plucked
// string model (a delay line fed back through a gentle low pass), so any
// pitch can sound without a recorded sample.
import { AudioProcessor } from "rive/audio";
import { Ring } from "rive/shared";

/// One pluck, sent from the scene to the audio thread.
export class Note {
    /// Pitch in Hz.
    frequency: f32 = 220;
    /// How hard it was struck, 0 to 1.
    gain: f32 = 0;
}

/// What the scene and the audio thread share.
export class Inputs {
    notes: Ring<Note> = Ring.create<Note>(4096);
}

const VOICES: i32 = 12;
// Samples each voice's delay line holds: a power of two, long enough for the
// lowest note at the highest output rate a device is likely to run at.
const LINE: i32 = 4096;
const LINE_MASK: i32 = LINE - 1;
const LOWEST: f32 = 55;
const HIGHEST: f32 = 2000;
// Seconds a note takes to fade to a thousandth at the lowest pitch.
const SUSTAIN: f32 = 5;

export class Pluck extends AudioProcessor<Inputs> {
    inputs: Inputs? = null;
    note: Note = new Note();
    channels: i32 = 2;
    rate: f32 = 48000;

    lines: StaticArray<f32> = new StaticArray<f32>(VOICES * LINE);
    // Where each voice writes next, and how far behind that it reads.
    heads: StaticArray<i32> = new StaticArray<i32>(VOICES);
    delays: StaticArray<f32> = new StaticArray<f32>(VOICES);
    // Feedback of each voice per sample pass, just under 1.
    feedbacks: StaticArray<f32> = new StaticArray<f32>(VOICES);
    // The last sample each voice read, for its low pass.
    lasts: StaticArray<f32> = new StaticArray<f32>(VOICES);
    // Samples each voice has left before it is taken as silent.
    lives: StaticArray<i32> = new StaticArray<i32>(VOICES);
    nextVoice: i32 = 0;
    seed: u32 = 22222;
    asleep: bool = true;

    override init(sampleRate: f64, maxFrames: i32, channels: i32, inputs: Inputs): void {
        this.inputs = inputs;
        this.channels = channels;
        this.rate = <f32>sampleRate;
    }

    // Noise in -1 to 1.
    private noise(): f32 {
        this.seed = this.seed * 1664525 + 1013904223;
        return <f32>(this.seed >>> 8) / 8388608.0 - 1.0;
    }

    // Starts `note` on the voice that has waited longest.
    private strike(note: Note): void {
        let frequency = note.frequency;
        // A comparison, not min and max, so a NaN cannot reach the cast below.
        if (!(frequency >= LOWEST)) {
            frequency = LOWEST;
        }
        if (frequency > HIGHEST) {
            frequency = HIGHEST;
        }
        let gain = note.gain;
        if (!(gain >= 0)) {
            gain = 0;
        }
        if (gain > 1) {
            gain = 1;
        }

        let voice = this.nextVoice;
        this.nextVoice = (voice + 1) % VOICES;

        // The low pass delays the loop by half a sample.
        let delay = this.rate / frequency - 0.5;
        if (delay > <f32>(LINE - 2)) {
            delay = <f32>(LINE - 2);
        }
        if (delay < 2) {
            delay = 2;
        }
        this.delays[voice] = delay;
        // High notes die sooner, as on a real string.
        let seconds = SUSTAIN * Mathf.sqrt(LOWEST / frequency) + 0.4;
        this.feedbacks[voice] = Mathf.pow(0.001, 1.0 / (frequency * seconds));
        this.lives[voice] = <i32>(this.rate * seconds * 1.2);
        this.lasts[voice] = 0;

        // One period of noise, softened more for a gentle pull than a hard
        // one, is the pluck.
        let base = voice * LINE;
        let head = this.heads[voice];
        let count = <i32>delay + 1;
        let soften = 0.85 - 0.6 * gain;
        let previous: f32 = 0;
        for (let i = 0; i < count; i++) {
            let raw = this.noise() * gain;
            previous = previous * soften + raw * (1.0 - soften);
            this.lines[base + ((head - count + i) & LINE_MASK)] = previous;
        }
    }

    override process(out: StaticArray<f32>, frames: i32, startFrame: f64): void {
        let inputs = this.inputs!;
        if (this.asleep && inputs.notes.used == 0) {
            return;
        }
        while (inputs.notes.receiveInto(this.note)) {
            this.strike(this.note);
        }

        let channels = this.channels;
        let anyAlive = false;
        for (let voice = 0; voice < VOICES; voice++) {
            let life = this.lives[voice];
            if (life <= 0) {
                continue;
            }
            anyAlive = true;
            let base = voice * LINE;
            let head = this.heads[voice];
            let delay = this.delays[voice];
            let whole = <i32>delay;
            let part = delay - <f32>whole;
            let feedback = this.feedbacks[voice];
            let last = this.lasts[voice];
            for (let i = 0; i < frames; i++) {
                let near = this.lines[base + ((head - whole) & LINE_MASK)];
                let far = this.lines[base + ((head - whole - 1) & LINE_MASK)];
                let sample = near + (far - near) * part;
                this.lines[base + (head & LINE_MASK)] = (sample + last) * 0.5 * feedback;
                last = sample;
                head = (head + 1) & LINE_MASK;
                let mixed = sample * 0.35;
                for (let c = 0; c < channels; c++) {
                    out[i * channels + c] += mixed;
                }
            }
            this.heads[voice] = head;
            this.lasts[voice] = last;
            this.lives[voice] = life - frames;
        }
        this.asleep = !anyAlive;
    }
}
