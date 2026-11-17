import { prepareIsolation } from "./isolation";
import type { GestureState, InstrumentState, Player } from "./player";
import "./bow.css";

const canvas = document.querySelector<HTMLCanvasElement>("#stage")!;
const report = document.querySelector<HTMLPreElement>("#report")!;
const notice = document.querySelector<HTMLDivElement>("#notice")!;
const status = document.querySelector<HTMLParagraphElement>("#status")!;
const playback = document.querySelector<HTMLButtonElement>("#playback")!;
const bowModeButton = document.querySelector<HTMLButtonElement>("#bow-mode")!;
const gestureHint = document.querySelector<HTMLParagraphElement>("#gesture-hint")!;
const bowStudio = document.querySelector<HTMLElement>("#bow-studio")!;
const bowPressure = document.querySelector<HTMLInputElement>("#bow-pressure")!;
const pressureValue = document.querySelector<HTMLOutputElement>("#pressure-value")!;
const bowState = document.querySelector<HTMLElement>("#bow-state")!;
const bowNote = document.querySelector<HTMLElement>("#bow-note")!;
const bowMeter = document.querySelector<HTMLElement>("#bow-meter")!;
const bowDirection = document.querySelector<HTMLElement>("#bow-direction")!;
const bowBlend = document.querySelector<HTMLButtonElement>("#bow-blend")!;
const practiceStrings = document.querySelector<HTMLButtonElement>("#practice-strings")!;
const bowStroke = document.querySelector<HTMLButtonElement>("#bow-stroke")!;
const bowPrevious = document.querySelector<HTMLButtonElement>("#bow-previous")!;
const bowNext = document.querySelector<HTMLButtonElement>("#bow-next")!;
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
let bowMode = false;
let gestureCursor = "crosshair";
let bowContacts = 0;
let bowLevel = 0;
let instrument: InstrumentState = { count: 0, selected: 0, frequency: 0, notesPlayed: 0 };

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
  practiceStrings.hidden = instrument.count > 0;
  practiceStrings.disabled = !ready;
  for (const button of [bowStroke, bowPrevious, bowNext]) button.disabled = !ready || instrument.count === 0;
  bowPressure.disabled = !ready;
  bowBlend.disabled = !ready;
  bowNote.textContent = instrument.count > 0 ? noteName(instrument.frequency) : "아직 현이 없어요";
  bowNote.setAttribute("aria-label", instrument.count > 0
    ? `선택한 현 ${instrument.selected}, ${noteName(instrument.frequency)}, ${numbers.format(instrument.frequency)} 헤르츠` : "아직 현이 없어요");
  updateGestureHint();
}

function noteName(frequency: number): string {
  const midi = Math.round(69 + 12 * Math.log2(frequency / 440));
  const names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"];
  return `${names[((midi % 12) + 12) % 12]}${Math.floor(midi / 12) - 1}`;
}

function updateInstrument(state: InstrumentState): void {
  const played = state.notesPlayed > instrument.notesPlayed;
  const startedPractice = instrument.count === 0 && state.count > 0 && document.activeElement === practiceStrings;
  instrument = state;
  const description = state.count === 0 ? "아직 현이 없습니다. 현 만들기를 눌러 시작하세요."
    : `전체 ${numbers.format(state.count)}개 중 ${numbers.format(state.selected)}번째 현 · ${numbers.format(state.frequency)}\u00a0Hz`;
  const message = played ? `선택한 현을 튕겼습니다. ${description}` : description;
  if (selection.textContent !== message) selection.textContent = message;
  updateInstrumentControls();
  if (startedPractice) bowStroke.focus();
}

function updatePlayback(): void {
  playback.hidden = failed;
  playback.setAttribute("aria-disabled", String(loading));
  playback.textContent = loading ? "준비 중…" : paused ? "재생" : "일시정지";
  canvas.inert = paused || loading || failed;
  bowModeButton.hidden = !player || failed;
  bowModeButton.setAttribute("aria-disabled", String(!canPlayInstrument()));
  bowStudio.hidden = !bowMode || !player || failed;
  document.body.classList.toggle("bowing", bowMode && Boolean(player));
  updateGestureHint();
  updateInstrumentControls();
}

function updateGestureHint(): void {
  gestureHint.hidden = !canPlayInstrument();
  gestureHint.textContent = bowMode
    ? instrument.count === 0 ? "연습 현을 놓거나, 활로 켜기를 끄고 나만의 현을 그려보세요"
    : bowContacts > 0
      ? bowLevel > 0 ? `${bowContacts}개의 현을 켜고 있어요 · 속도로 소리의 크기를 조절하세요`
      : `${bowContacts}개의 현에 활이 닿아 있어요 · 활의 긴 방향으로 왕복하세요`
      : "현 위에 활을 대고, 누른 채 활의 긴 방향으로 움직이세요"
    : gestureCursor === "grabbing" ? "현을 잡았어요 · 당겼다가 놓으세요"
    : gestureCursor === "grab" ? "현을 잡으려면 누른 채 당기세요"
    : "빈 곳을 드래그해 현을 만드세요";
  bowState.textContent = !canPlayInstrument() ? "잠시 멈춤"
    : instrument.count === 0 ? "첫 소리를 준비하세요"
    : bowLevel > 0 ? `${bowContacts || 1}개 현이 울리는 중`
    : gestureCursor === "grabbing" ? "천천히 움직여보세요"
    : bowContacts > 0 ? "활을 움직이면 소리가 나요" : "활을 현에 대어보세요";
  bowStudio.dataset.sounding = String(bowLevel > 0 && canPlayInstrument());
  bowMeter.style.setProperty("--level", String(canPlayInstrument() ? bowLevel : 0));
}

function updateGesture(state: GestureState): void {
  gestureCursor = state.cursor;
  bowContacts = state.contacts;
  bowLevel = state.level;
  bowDirection.dataset.direction = state.direction > 0 ? "forward" : "backward";
  updateGestureHint();
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

bowModeButton.addEventListener("click", () => {
  if (!canPlayInstrument()) return;
  bowMode = !bowMode;
  bowModeButton.setAttribute("aria-pressed", String(bowMode));
  player!.setBowMode(bowMode);
  bowContacts = 0;
  bowLevel = 0;
  updatePlayback();
}, { signal: events.signal });

bowPressure.addEventListener("input", () => {
  const value = Number(bowPressure.value);
  player?.setBowPressure(value / 100);
  const label = value < 35 ? "가볍게" : value < 70 ? "보통" : "단단하게";
  pressureValue.value = label;
  bowPressure.setAttribute("aria-valuetext", `${label}, ${value}%`);
}, { signal: events.signal });
bowBlend.addEventListener("click", () => {
  if (!canPlayInstrument()) return;
  const together = bowBlend.getAttribute("aria-pressed") !== "true";
  bowBlend.setAttribute("aria-pressed", String(together));
  player!.setBowPolyphonic(together);
}, { signal: events.signal });
practiceStrings.addEventListener("click", () => {
  if (canPlayInstrument() && instrument.count === 0) player!.practiceStrings();
}, { signal: events.signal });
bowStroke.addEventListener("click", () => {
  if (canPlayInstrument() && instrument.count > 0) player!.bowStroke();
}, { signal: events.signal });
bowPrevious.addEventListener("click", () => {
  if (canPlayInstrument()) player!.selectString(-1);
}, { signal: events.signal });
bowNext.addEventListener("click", () => {
  if (canPlayInstrument()) player!.selectString(1);
}, { signal: events.signal });
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
updatePlayback();
if (paused) {
  announce("움직임 줄이기 설정이 켜져 있습니다. 재생을 누르면 현과 파문이 움직입니다.");
} else {
  void start();
}
