import { prepareIsolation } from "./isolation";
import type { Player } from "./player";

const canvas = document.querySelector<HTMLCanvasElement>("#stage")!;
const report = document.querySelector<HTMLPreElement>("#report")!;
const notice = document.querySelector<HTMLDivElement>("#notice")!;
const status = document.querySelector<HTMLParagraphElement>("#status")!;
const loadingMessage = document.querySelector<HTMLParagraphElement>("#loading")!;
const playback = document.querySelector<HTMLButtonElement>("#playback")!;
const retry = document.querySelector<HTMLButtonElement>("#retry")!;
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

function note(line: string): void {
  if (debug) {
    lines.push(line);
    if (lines.length > 50) lines.shift();
    report.hidden = false;
    report.textContent = lines.join("\n");
  }
  console.info(`[janhyang] ${line}`);
}

function announce(message: string): void {
  status.textContent = message;
  notice.classList.toggle("message", Boolean(message));
}

function updatePlayback(): void {
  playback.hidden = failed;
  playback.setAttribute("aria-disabled", String(loading));
  playback.textContent = loading ? "준비 중…" : paused ? "재생" : "일시정지";
  canvas.inert = paused || loading || failed;
}

function fail(error: unknown): void {
  if (disposed) return;
  note(`load error: ${String(error)}`);
  failed = true;
  loading = false;
  loadingMessage.hidden = true;
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
  loadingMessage.hidden = false;
  announce("");
  updatePlayback();
  try {
    // Do not initialize WASM in the document the isolation worker will replace.
    if (await isolation === "reloading" || disposed) return;
    const { createPlayer } = await import("./player");
    if (disposed) return;
    const loaded = await createPlayer(canvas, note);
    if (disposed) {
      loaded.cleanup();
      return;
    }
    player = loaded;
    loading = false;
    loadingMessage.hidden = true;
    if (paused) {
      player.pause();
      announce("움직임을 멈췄습니다. 재생을 누르면 현과 파문이 움직입니다.");
    } else {
      player.play();
      announce(audioNotice);
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

updatePlayback();
if (paused) {
  announce("움직임 줄이기 설정이 켜져 있습니다. 재생을 누르면 현과 파문이 움직입니다.");
} else {
  void start();
}
