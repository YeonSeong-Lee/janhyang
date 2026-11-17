export const harmonies = [
  { name: "차분하게", chord: "Am", notes: [9, 0, 4], syllables: ["라", "도", "미"], hint: "라·도·미가 차분하게 어울려요." },
  { name: "맑게", chord: "C", notes: [0, 4, 7], syllables: ["도", "미", "솔"], hint: "도·미·솔이 맑게 어울려요." },
  { name: "따뜻하게", chord: "F", notes: [5, 9, 0], syllables: ["파", "라", "도"], hint: "파·라·도가 따뜻하게 어울려요." },
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
