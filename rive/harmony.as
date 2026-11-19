// Optional starter chords. These never tune a user's drawn strings.
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
