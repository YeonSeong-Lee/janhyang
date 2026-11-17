// A compact bowed-string waveguide. Two fractional delays carry waves from
// the contact to the fixed ends and back. Relative bow/string velocity drives
// a bounded, velocity-dependent friction junction. This is an expressive
// instrument model, not a measured acoustic violin. See docs/bowing.md.
const SIZE: i32 = 4096;
const MASK: i32 = SIZE - 1;

export class BowedVoice {
    neck: StaticArray<f32> = new StaticArray<f32>(SIZE);
    bridge: StaticArray<f32> = new StaticArray<f32>(SIZE);
    head: i32 = 0;
    rate: f32 = 48000;
    frequency: f32 = 220;
    target: f32 = 0;
    velocity: f32 = 0;
    pressure: f32 = 0.5;
    position: f32 = 0.18;
    balance: f32 = 1;
    level: f32 = 0;
    life: i32 = 0;
    filtered: f32 = 0;
    body: f32 = 0;
    dc: f32 = 0;
    previous: f32 = 0;
    attack: f32 = 0;
    release: f32 = 0;
    pole: f32 = 0;
    bodyPole: f32 = 0;

    init(rate: f32): void {
        this.rate = rate;
        this.attack = 1 - Mathf.exp(-1 / (rate * 0.012));
        this.release = 1 - Mathf.exp(-1 / (rate * 0.045));
        this.pole = Mathf.exp(-2 * Mathf.PI * 6500 / rate);
        this.bodyPole = Mathf.exp(-2 * Mathf.PI * 4200 / rate);
    }

    update(frequency: f32, gain: f32, velocity: f32, pressure: f32, position: f32): void {
        if (!(frequency >= 55 && frequency <= 2000)) frequency = 220;
        if (!(gain >= 0 && gain <= 1)) gain = 0;
        if (!(velocity >= -1 && velocity <= 1)) velocity = 0;
        if (!(pressure >= 0 && pressure <= 1)) pressure = 0.5;
        if (!(position >= 0 && position <= 1)) position = 0.5;
        // Voice slots may be reused after an old string is retired. Do not
        // pitch-shift that old delay memory into the new instrument.
        if (Mathf.abs(frequency - this.frequency) > 0.1) this.clear();
        this.frequency = frequency;
        this.target = gain > 0 ? velocity * 0.22 : 0;
        this.balance = gain;
        this.pressure = pressure;
        // Fold about the centre. A real contact near an anchor is brighter;
        // the playable range avoids pathological rational delay ratios.
        this.position = 0.07 + Mathf.min(position, 1 - position) * 0.4;
        this.life = <i32>(this.rate * 0.15);
    }

    private clear(): void {
        for (let i = 0; i < SIZE; i++) { this.neck[i] = 0; this.bridge[i] = 0; }
        this.filtered = 0;
        this.body = 0;
        this.previous = 0;
        this.dc = 0;
    }

    private read(line: StaticArray<f32>, delay: f32): f32 {
        let whole = <i32>delay;
        let fraction = delay - <f32>whole;
        let near = line[(this.head - whole) & MASK];
        return near + (line[(this.head - whole - 1) & MASK] - near) * fraction;
    }

    get active(): bool { return this.life > 0 || this.level > 0.00001; }

    tick(): f32 {
        if (--this.life <= 0) this.target = 0;
        let playing = Mathf.abs(this.target) > 0.001 && this.pressure > 0;
        this.velocity += (this.target - this.velocity) * this.attack;
        let envelope = playing ? this.balance : 0;
        this.level += (envelope - this.level) * (envelope > this.level ? this.attack : this.release);
        if (this.level < 0.00001 && !playing) {
            this.level = 0;
            this.velocity = 0;
            return 0;
        }
        // Compensate the bridge low-pass's group delay at low frequencies.
        let period = this.rate / this.frequency - this.pole / (1 - this.pole);
        let fromNeck = -this.read(this.neck, Mathf.max(2, period * (1 - this.position)));
        let arriving = this.read(this.bridge, Mathf.max(2, period * this.position));
        this.filtered = arriving * (1 - this.pole) + this.filtered * this.pole;
        let fromBridge = -this.filtered * 0.985;
        let relative = this.velocity - fromNeck - fromBridge;
        let frictionWidth = 6 - this.pressure * 4.5;
        let curve = Mathf.abs(relative) * frictionWidth + 0.75;
        let squared = curve * curve;
        let friction = Mathf.min(0.98, 1 / (squared * squared));
        let drive = playing ? relative * friction : 0;
        // Clamp the internal waves as well as the final mix; malformed or
        // extreme control input cannot grow an unbounded feedback loop.
        this.neck[this.head] = Mathf.max(-2, Mathf.min(2, fromBridge + drive));
        this.bridge[this.head] = Mathf.max(-2, Mathf.min(2, fromNeck + drive));
        this.head = (this.head + 1) & MASK;
        this.body = arriving * (1 - this.bodyPole) + this.body * this.bodyPole;
        let output = this.body - this.previous + 0.995 * this.dc;
        this.previous = this.body;
        this.dc = output;
        return output * this.level * 0.65;
    }
}
