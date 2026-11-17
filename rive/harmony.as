// A small palette of chord tones. Geometry stays free; only pitch is tuned.
// 0: A minor, 1: C major, 2: F major. Keep the IDs in web/src/harmony.ts.
export function harmonyId(value: f64): i32 {
    return value == 1 ? 1 : value == 2 ? 2 : 0;
}

export function chordMidi(harmony: i32, degree: i32): i32 {
    let root = harmony == 1 ? 60 : harmony == 2 ? 53 : 57;
    return root + (degree == 1 ? (harmony == 0 ? 3 : 4) : degree == 2 ? 7 : 0);
}

export function frequencyOf(midi: f64): f64 {
    return 440 * Math.pow(2, (midi - 69) / 12);
}

export function naturalMidi(length: f64, height: f64): f64 {
    return 57 + 12 * Math.log2(Math.max(height, 1) / Math.max(length, 1));
}

export function tunedPitch(midi: f64, harmony: i32): f64 {
    let nearest = chordMidi(harmony, 0);
    let distance: f64 = Infinity;
    // Bound the candidates, never the final frequency: the extremes must
    // still belong to the chord, even for a very short stroke on a phone.
    for (let candidate = 48; candidate <= 81; candidate++) {
        let allowed = false;
        for (let degree = 0; degree < 3; degree++) {
            if (candidate % 12 == chordMidi(harmony, degree) % 12) allowed = true;
        }
        let gap = Math.abs(candidate - midi);
        if (allowed && gap < distance) {
            nearest = candidate;
            distance = gap;
        }
    }
    return frequencyOf(nearest);
}
