import { prepareIsolation } from "./isolation";
import type { GestureState, InstrumentState, Player } from "./player";
import { harmonies, midiOf, noteName } from "./harmony";
import "./harmony.css";

const canvas = document.querySelector<HTMLCanvasElement>("#stage")!;
const report = document.querySelector<HTMLPreElement>("#report")!;
const notice = document.querySelector<HTMLDivElement>("#notice")!;
const status = document.querySelector<HTMLParagraphElement>("#status")!;
const playback = document.querySelector<HTMLButtonElement>("#playback")!;
const gestureHint = document.querySelector<HTMLParagraphElement>("#gesture-hint")!;
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
const harmonyPanel = document.querySelector<HTMLElement>("#harmony-panel")!;
const harmonyBody = document.querySelector<HTMLElement>("#harmony-body")!;
const harmonyToggle = document.querySelector<HTMLButtonElement>("#harmony-toggle")!;
const harmonyMood = document.querySelector<HTMLSelectElement>("#harmony-mood")!;
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
let player: Player | undefined;
let paused = motion.matches;
let loading = false;
let failed = false;
let disposed = false;
let gestureCursor = "crosshair";
let instrument: InstrumentState = { count: 0, selected: 0, frequency: 0, notesPlayed: 0, demoPlaying: false };
let gesture: GestureState = { cursor: "crosshair", drawing: false, previewFrequency: 0 };
let harmonyIndex = 0;

function updateHarmony(): void {
  const ready = canPlayInstrument();
  harmonyPanel.hidden = help.open;
  harmonyMood.disabled = !ready;
  harmonySeed.hidden = instrument.count > 0;
  harmonyPluck.hidden = instrument.count === 0;
  harmonySeed.setAttribute("aria-disabled", String(!ready));
  harmonyPluck.setAttribute("aria-disabled", String(!ready || instrument.count === 0));
  harmonyDemo.setAttribute("aria-disabled", String(!ready || instrument.count === 0));
  const demo = ready && instrument.demoPlaying;
  harmonyDemo.setAttribute("aria-pressed", String(demo));
  harmonyDemo.textContent = demo ? "예시 연주 멈추기" : "짧은 연주 듣기";
  harmonyPanel.dataset.drawing = String(ready && gesture.drawing);
  const frequency = gesture.drawing ? gesture.previewFrequency : instrument.frequency;
  const name = noteName(frequency);
  harmonyNote.textContent = name;
  harmonyNote.setAttribute("aria-label", `${gesture.drawing ? "만들고 있는" : "선택한"} 현의 음 ${name}`);
  const pitchClass = frequency > 0 ? ((midiOf(frequency) % 12) + 12) % 12 : -1;
  for (const tone of harmonyNotes.children) {
    (tone as HTMLElement).dataset.active = String(Number((tone as HTMLElement).dataset.pitch) === pitchClass);
  }
  const message = failed ? "다시 불러온 뒤 소리를 만들 수 있어요."
    : loading ? "수면과 소리를 준비하고 있어요."
    : !ready ? "재생을 누르면 시작할 수 있어요."
    : gesture.drawing ? frequency > 0 ? `${name}에 맞춰졌어요. 손을 놓으면 현이 완성돼요.` : "조금 더 길게 그어보세요."
    : demo ? "지금 만든 현으로 연주 중이에요. 직접 만지면 멈춰요."
    : instrument.count === 0 ? "자유롭게 그려도 어울리는 음으로 맞춰져요."
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

function canPlayInstrument(): boolean {
  return Boolean(player) && !paused && !loading && !failed;
}

function updateInstrumentControls(): void {
  const ready = canPlayInstrument();
  createString.setAttribute("aria-disabled", String(!ready));
  for (const button of [previousString, nextString, pluckString]) {
    button.setAttribute("aria-disabled", String(!ready || instrument.count === 0));
  }
  instrumentHint.textContent = failed ? "다시 불러온 뒤 연주할 수 있습니다."
    : loading ? "수면을 준비하고 있습니다…"
    : !ready ? "재생을 누른 뒤 현을 만들고 연주할 수 있습니다."
    : "Tab으로 이동하고 Enter 또는 Space로 버튼을 누르세요. 선택한 현에는 밝은 점이 표시됩니다.";
  updateGestureHint();
  updateHarmony();
}

function updateInstrument(state: InstrumentState): void {
  const played = state.notesPlayed > instrument.notesPlayed;
  const seeded = instrument.count === 0 && state.count > 0 && document.activeElement === harmonySeed;
  instrument = state;
  const description = state.count === 0 ? "아직 현이 없습니다. 현 만들기를 눌러 시작하세요."
    : `전체 ${numbers.format(state.count)}개 중 ${numbers.format(state.selected)}번째 현 · ${noteName(state.frequency)} · ${numbers.format(state.frequency)}\u00a0Hz`;
  const message = played ? `선택한 현을 튕겼습니다. ${description}` : description;
  if (selection.textContent !== message) selection.textContent = message;
  updateInstrumentControls();
  if (seeded) harmonyDemo.focus();
}

function updatePlayback(): void {
  playback.hidden = failed;
  playback.setAttribute("aria-disabled", String(loading));
  playback.textContent = loading ? "준비 중…" : paused ? "재생" : "일시정지";
  canvas.inert = paused || loading || failed;
  updateGestureHint();
  updateInstrumentControls();
}

function updateGestureHint(): void {
  gestureHint.hidden = !canPlayInstrument();
  gestureHint.textContent = gestureCursor === "grabbing" ? "현을 잡았어요 · 당겼다가 놓으세요"
    : gestureCursor === "grab" ? "현을 잡으려면 누른 채 당기세요"
    : gesture.drawing ? gesture.previewFrequency > 0 ? `${noteName(gesture.previewFrequency)} · 손을 놓으면 현이 완성돼요` : "조금 더 길게 그어보세요"
    : "빈 곳을 드래그해 현을 만드세요";
}

function updateGesture(state: GestureState): void {
  gesture = state;
  gestureCursor = state.cursor;
  updateGestureHint();
  updateHarmony();
}

function fail(error: unknown): void {
  if (disposed) return;
  note(`load error: ${String(error)}`);
  failed = true;
  loading = false;
  retry.hidden = false;
  announce("화면을 불러오지 못했습니다. 연결을 확인한 뒤 다시 불러와 주세요.");
  // Preserve keyboard focus when replacing the playback control with retry.
  if (document.activeElement === playback) retry.focus();
  updatePlayback();
}

const isolation = prepareIsolation(
  new URL(`${import.meta.env.BASE_URL}coi.js`, document.baseURI),
  note,
);

async function start(): Promise<void> {
  if (loading || failed || disposed) return;
  loading = true;
  announce("수면을 준비하고 있습니다…");
  updatePlayback();
  try {
    // Do not initialize WASM in the document the isolation worker will replace.
    if (await isolation === "reloading" || disposed) return;
    const { createPlayer } = await import("./player");
    if (disposed) return;
    const loaded = await createPlayer(canvas, note, updateInstrument, updateGesture);
    if (disposed) {
      loaded.cleanup();
      return;
    }
    player = loaded;
    player.setHarmony(harmonyIndex);
    loading = false;
    if (paused) {
      player.pause();
      announce("움직임을 멈췄습니다. 재생을 누르면 현과 파문이 움직입니다.");
    } else {
      player.play();
      announce(audioNotice || "수면을 준비했습니다. 연주할 수 있습니다.", Boolean(audioNotice));
    }
    updatePlayback();
  } catch (error) {
    fail(error);
  }
}

playback.addEventListener("click", () => {
  if (loading || failed) return;
  paused = !paused;
  if (!player) {
    void start();
    return;
  }
  if (paused) player.pause();
  else player.play();
  announce(paused ? "" : audioNotice);
  updatePlayback();
}, { signal: events.signal });

retry.addEventListener("click", () => location.reload(), { signal: events.signal });

harmonyMood.addEventListener("change", () => {
  if (!canPlayInstrument()) return;
  harmonyIndex = Number(harmonyMood.value);
  player!.setHarmony(harmonyIndex);
  showHarmony();
}, { signal: events.signal });
harmonySeed.addEventListener("click", () => {
  if (canPlayInstrument() && instrument.count === 0) player!.harmonyStrings();
}, { signal: events.signal });
harmonyPluck.addEventListener("click", () => {
  if (canPlayInstrument() && instrument.count > 0) player!.pluckString(Number(strength.value));
}, { signal: events.signal });
harmonyDemo.addEventListener("click", () => {
  if (canPlayInstrument() && instrument.count > 0) player!.playPhrase();
}, { signal: events.signal });
harmonyToggle.addEventListener("click", () => {
  const collapsed = !harmonyBody.hidden;
  harmonyBody.hidden = collapsed;
  harmonyPanel.dataset.collapsed = String(collapsed);
  harmonyToggle.textContent = collapsed ? "펼치기" : "접기";
  harmonyToggle.setAttribute("aria-expanded", String(!collapsed));
}, { signal: events.signal });
help.addEventListener("toggle", updateHarmony, { signal: events.signal });

window.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && canPlayInstrument()) player!.stopGesture();
}, { signal: events.signal });

createString.addEventListener("click", () => {
  if (canPlayInstrument()) player!.createString(Number(stringLength.value));
}, { signal: events.signal });
previousString.addEventListener("click", () => {
  if (canPlayInstrument() && instrument.count > 0) player!.selectString(-1);
}, { signal: events.signal });
nextString.addEventListener("click", () => {
  if (canPlayInstrument() && instrument.count > 0) player!.selectString(1);
}, { signal: events.signal });
pluckString.addEventListener("click", () => {
  if (canPlayInstrument() && instrument.count > 0) player!.pluckString(Number(strength.value));
}, { signal: events.signal });

motion.addEventListener("change", () => {
  // A preference change can stop motion, but never restarts it without intent.
  if (motion.matches && !failed) {
    paused = true;
    player?.pause();
    announce("움직임 줄이기 설정에 따라 멈췄습니다. 재생을 누르면 다시 시작합니다.");
    updatePlayback();
  }
}, { signal: events.signal });

window.addEventListener("error", (event) => note(`error: ${event.message}`), { signal: events.signal });
window.addEventListener("unhandledrejection", (event) => note(`rejection: ${String(event.reason)}`), { signal: events.signal });

function cleanup(): void {
  disposed = true;
  events.abort();
  player?.cleanup();
}

// A bfcache entry must keep its player; the runtime handles tab visibility.
window.addEventListener("pagehide", (event) => {
  if (!event.persisted) cleanup();
}, { signal: events.signal });
if (import.meta.hot) import.meta.hot.dispose(cleanup);

instrumentControls.hidden = false;
showHarmony();
updatePlayback();
if (paused) {
  announce("움직임 줄이기 설정이 켜져 있습니다. 재생을 누르면 현과 파문이 움직입니다.");
} else {
  void start();
}
