import { prepareIsolation } from "./isolation";
import type { GestureState, InstrumentState } from "./player";
import { harmonies, midiOf, noteName, centsFromNote, pitchLabel } from "./harmony";
import { createDragGuide } from "./drag-guide";
import { createPointerSession } from "./pointer-session";
import { createPlaybackSession, type PlaybackState } from "./playback-session";
import "./harmony.css";

const canvas = document.querySelector<HTMLCanvasElement>("#stage")!;
const report = document.querySelector<HTMLPreElement>("#report")!;
const notice = document.querySelector<HTMLDivElement>("#notice")!;
const status = document.querySelector<HTMLParagraphElement>("#status")!;
const loadingScreen = document.querySelector<HTMLElement>("#loading-screen")!;
const loadingCaption = document.querySelector<HTMLParagraphElement>("#loading-caption")!;
const playback = document.querySelector<HTMLButtonElement>("#playback")!;
const retry = document.querySelector<HTMLButtonElement>("#retry")!;
const instrumentControls = document.querySelector<HTMLFieldSetElement>("#instrument-controls")!;
const instrumentHint = document.querySelector<HTMLParagraphElement>("#instrument-hint")!;
const selection = document.querySelector<HTMLParagraphElement>("#selection")!;
const stringLength = document.querySelector<HTMLSelectElement>("#string-length")!;
const strength = document.querySelector<HTMLSelectElement>("#pluck-strength")!;
const createString = document.querySelector<HTMLButtonElement>("#create-string")!;
const previousString = document.querySelector<HTMLButtonElement>("#previous-string")!;
const nextString = document.querySelector<HTMLButtonElement>("#next-string")!;
const pluckString = document.querySelector<HTMLButtonElement>("#pluck-string")!;
const harmonyMood = document.querySelector<HTMLSelectElement>("#harmony-mood")!;
const harmonyGuide = document.querySelector<HTMLInputElement>("#harmony-guide")!;
const harmonyChord = document.querySelector<HTMLElement>("#harmony-chord")!;
const harmonyNotes = document.querySelector<HTMLElement>("#harmony-notes")!;
const harmonyNote = document.querySelector<HTMLElement>("#harmony-note")!;
const harmonyDescription = document.querySelector<HTMLElement>("#harmony-description")!;
const harmonyFeedback = document.querySelector<HTMLElement>("#harmony-feedback")!;
const harmonySeed = document.querySelector<HTMLButtonElement>("#harmony-seed")!;
const harmonyPluck = document.querySelector<HTMLButtonElement>("#harmony-pluck")!;
const harmonyDemo = document.querySelector<HTMLButtonElement>("#harmony-demo")!;
const help = document.querySelector<HTMLDetailsElement>(".controls details")!;
const numbers = new Intl.NumberFormat("ko-KR", { maximumFractionDigits: 0 });
const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
const audioNotice = window.crossOriginIsolated
  ? ""
  : "이 브라우저 환경에서는 소리를 재생할 수 없어 화면만 표시합니다.";
const debug = new URLSearchParams(location.search).has("debug");
const lines: string[] = [];
const events = new AbortController();
let instrument: InstrumentState = { count: 0, selected: 0, frequency: 0, notesPlayed: 0, demoPlaying: false };
let gesture: GestureState = { cursor: "crosshair", drawing: false, previewFrequency: 0 };
let harmonyIndex = 0;
const dragGuide = createDragGuide(canvas, () => harmonyGuide.checked ? harmonyIndex : null);
const pointerSession = createPointerSession(canvas, {
  enabled: canPlayInstrument,
  guideEnabled: () => !help.open,
  show: dragGuide.render,
  stop: () => session.player?.stopGesture(),
});

const isolation = prepareIsolation(new URL(`${import.meta.env.BASE_URL}coi.js`, document.baseURI), note);
const session = createPlaybackSession({
  reducedMotion: motion.matches,
  audioNotice,
  load: async (signal) => {
    if (await isolation === "reloading" || signal.aborted) return;
    const { createPlayer } = await import("./player");
    if (signal.aborted) return;
    const player = await createPlayer(canvas, note, updateInstrument, updateGesture);
    player.setHarmony(harmonyIndex);
    return player;
  },
  changed: renderPlayback,
  failed: (error) => note(`load error: ${String(error)}`),
});

function updateHarmony(): void {
  const ready = canPlayInstrument();
  harmonyMood.disabled = !ready;
  harmonySeed.hidden = instrument.count > 0;
  harmonyPluck.hidden = instrument.count === 0;
  harmonySeed.setAttribute("aria-disabled", String(!ready));
  harmonyPluck.setAttribute("aria-disabled", String(!ready || instrument.count === 0));
  harmonyDemo.setAttribute("aria-disabled", String(!ready || instrument.count === 0));
  const demo = ready && instrument.demoPlaying;
  harmonyDemo.setAttribute("aria-pressed", String(demo));
  harmonyDemo.textContent = demo ? "예시 연주 멈추기" : "짧은 연주 듣기";
  const frequency = gesture.drawing ? gesture.previewFrequency : instrument.frequency;
  const name = noteName(frequency);
  harmonyNote.textContent = name;
  harmonyNote.setAttribute("aria-label", `${gesture.drawing ? "만들고 있는" : "선택한"} 현의 음 ${pitchLabel(frequency)}`);
  const pitchClass = frequency > 0 && Math.abs(centsFromNote(frequency)) < 1 ? ((midiOf(frequency) % 12) + 12) % 12 : -1;
  for (const tone of harmonyNotes.children) {
    (tone as HTMLElement).dataset.active = String(Number((tone as HTMLElement).dataset.pitch) === pitchClass);
  }
  const message = session.state.phase === "failed" ? "다시 불러온 뒤 소리를 만들 수 있어요."
    : session.state.phase === "loading" ? "수면과 소리를 준비하고 있어요."
    : !ready ? "재생을 누르면 시작할 수 있어요."
    : gesture.drawing ? frequency > 0 ? `${pitchLabel(frequency)}. 그린 길이 그대로 울려요.` : "조금 더 길게 그어보세요."
    : demo ? "지금 만든 현으로 연주 중이에요. 직접 만지면 멈춰요."
    : instrument.count === 0 ? "그린 길이가 곧 음높이예요. 자동으로 조율하지 않아요."
    : instrument.count < 3 ? "길이를 달리해 현을 더 그어보세요. 긴 현은 낮게 울려요."
    : "현을 당겼다 놓아 나만의 순서로 연주해 보세요.";
  if (harmonyFeedback.textContent !== message) harmonyFeedback.textContent = message;
}

function showHarmony(): void {
  const harmony = harmonies[harmonyIndex];
  harmonyChord.textContent = harmony.chord;
  harmonyDescription.textContent = harmony.hint;
  harmonyNotes.replaceChildren(...harmony.notes.map((pitch, i) => {
    const tone = document.createElement("span");
    tone.className = "harmony-tone";
    tone.dataset.pitch = String(pitch);
    tone.textContent = harmony.syllables[i];
    return tone;
  }));
  updateHarmony();
}

function note(line: string): void {
  if (debug) {
    lines.push(line);
    if (lines.length > 50) lines.shift();
    report.hidden = false;
    report.textContent = lines.join("\n");
  }
  console.info(`[janhyang] ${line}`);
}

function announce(message: string, visible = true): void {
  status.textContent = message;
  status.classList.toggle("visually-hidden", !visible);
  notice.classList.toggle("message", visible && Boolean(message));
}

function canPlayInstrument(): boolean { return session.canPlay; }

function updateInstrumentControls(): void {
  const ready = canPlayInstrument();
  createString.setAttribute("aria-disabled", String(!ready));
  for (const button of [previousString, nextString, pluckString]) {
    button.setAttribute("aria-disabled", String(!ready || instrument.count === 0));
  }
  instrumentHint.textContent = session.state.phase === "failed" ? "다시 불러온 뒤 연주할 수 있습니다."
    : session.state.phase === "loading" ? "수면을 준비하고 있습니다…"
    : !ready ? "재생을 누른 뒤 현을 만들고 연주할 수 있습니다."
    : "Tab으로 이동하고 Enter 또는 Space로 버튼을 누르세요. 선택한 현에는 밝은 점이 표시됩니다.";
  if (!ready) pointerSession.cancel();
  updateHarmony();
}

function updateInstrument(state: InstrumentState): void {
  const played = state.notesPlayed > instrument.notesPlayed;
  const seeded = instrument.count === 0 && state.count > 0 && document.activeElement === harmonySeed;
  instrument = state;
  const description = state.count === 0 ? "아직 현이 없습니다. 현 만들기를 눌러 시작하세요."
    : `전체 ${numbers.format(state.count)}개 중 ${numbers.format(state.selected)}번째 현 · ${pitchLabel(state.frequency)}`;
  const message = played ? `선택한 현을 튕겼습니다. ${description}` : description;
  if (selection.textContent !== message) selection.textContent = message;
  updateInstrumentControls();
  if (seeded) harmonyDemo.focus();
}

function renderPlayback(state: Readonly<PlaybackState>): void {
  const loading = state.phase === "loading";
  const failed = state.phase === "failed";
  loadingScreen.hidden = state.curtain === "hidden";
  loadingScreen.setAttribute("aria-hidden", String(state.curtain !== "visible"));
  loadingScreen.dataset.state = state.curtain === "leaving" ? "leaving" : "loading";
  loadingCaption.textContent = state.slow ? "준비가 조금 길어지고 있어요" : "수면과 소리를 준비하고 있어요";
  announce(state.announcement, state.visibleAnnouncement);
  retry.hidden = !failed;
  if (failed && document.activeElement === playback) retry.focus();
  playback.hidden = failed;
  playback.setAttribute("aria-disabled", String(loading));
  playback.textContent = loading ? "준비 중…" : state.phase === "playing" ? "일시정지" : "재생";
  canvas.inert = state.phase !== "playing";
  updateInstrumentControls();
}

function updateGesture(state: GestureState): void {
  gesture = state;
  pointerSession.observe(state);
  updateHarmony();
}

playback.addEventListener("click", () => session.toggle(), { signal: events.signal });

retry.addEventListener("click", () => location.reload(), { signal: events.signal });

harmonyMood.addEventListener("change", () => {
  if (!canPlayInstrument()) return;
  harmonyIndex = Number(harmonyMood.value);
  session.player!.setHarmony(harmonyIndex);
  showHarmony();
}, { signal: events.signal });
harmonySeed.addEventListener("click", () => {
  if (canPlayInstrument() && instrument.count === 0) session.player!.harmonyStrings();
}, { signal: events.signal });
harmonyPluck.addEventListener("click", () => {
  if (canPlayInstrument() && instrument.count > 0) session.player!.pluckString(Number(strength.value));
}, { signal: events.signal });
harmonyDemo.addEventListener("click", () => {
  if (canPlayInstrument() && instrument.count > 0) session.player!.playPhrase();
}, { signal: events.signal });
help.addEventListener("toggle", () => {
  if (help.open) {
    pointerSession.cancel();
  }
}, { signal: events.signal });

window.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && canPlayInstrument()) {
    pointerSession.cancel();
  }
}, { signal: events.signal });

createString.addEventListener("click", () => {
  if (canPlayInstrument()) session.player!.createString(Number(stringLength.value));
}, { signal: events.signal });
previousString.addEventListener("click", () => {
  if (canPlayInstrument() && instrument.count > 0) session.player!.selectString(-1);
}, { signal: events.signal });
nextString.addEventListener("click", () => {
  if (canPlayInstrument() && instrument.count > 0) session.player!.selectString(1);
}, { signal: events.signal });
pluckString.addEventListener("click", () => {
  if (canPlayInstrument() && instrument.count > 0) session.player!.pluckString(Number(strength.value));
}, { signal: events.signal });

motion.addEventListener("change", () => session.setReducedMotion(motion.matches), { signal: events.signal });

window.addEventListener("error", (event) => note(`error: ${event.message}`), { signal: events.signal });
window.addEventListener("unhandledrejection", (event) => note(`rejection: ${String(event.reason)}`), { signal: events.signal });

function cleanup(persisted = false): void {
  session.dispose(persisted);
  if (persisted) return;
  events.abort();
  pointerSession.cleanup();
}

window.addEventListener("pagehide", (event) => cleanup(event.persisted), { signal: events.signal });
if (import.meta.hot) import.meta.hot.dispose(() => cleanup());

instrumentControls.hidden = false;
showHarmony();
session.start();
