import { frequencies, translate } from "./i18n";

export const harmonies = [
  { chord: "Am", notes: [9, 0, 4], hint: "calmHint" },
  { chord: "C", notes: [0, 4, 7], hint: "clearHint" },
  { chord: "F", notes: [5, 9, 0], hint: "warmHint" },
] as const;

const names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"];

export function midiOf(frequency: number): number {
  return Math.round(69 + 12 * Math.log2(frequency / 440));
}

export function noteName(frequency: number): string {
  if (!(frequency > 0)) return "—";
  const midi = midiOf(frequency);
  return `${names[((midi % 12) + 12) % 12]}${Math.floor(midi / 12) - 1}`;
}

export function centsFromNote(frequency: number): number {
  return (69 + 12 * Math.log2(frequency / 440) - midiOf(frequency)) * 100;
}

export function pitchLabel(frequency: number): string {
  return frequency > 0 ? translate("pitch", { note: noteName(frequency), hz: frequencies.format(frequency) }) : "—";
}

/** An optional visual reference only. Never passed back to the sound engine. */
export function referenceFrequency(frequency: number, harmony: number): number {
  if (!(frequency > 0) || !Number.isFinite(frequency)) return 0;
  const midi = 69 + 12 * Math.log2(frequency / 440);
  const octave = Math.floor(midi / 12);
  let nearest = 0;
  let distance = Infinity;
  for (let offset = -1; offset <= 1; offset++) {
    for (const pitch of (harmonies[harmony] ?? harmonies[0]).notes) {
      const candidate = (octave + offset) * 12 + pitch;
      const gap = Math.abs(candidate - midi);
      if (gap < distance) {
        nearest = candidate;
        distance = gap;
      }
    }
  }
  return 440 * 2 ** ((nearest - 69) / 12);
}
