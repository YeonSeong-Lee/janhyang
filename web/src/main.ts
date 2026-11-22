import { locale, messages, numbers, setLanguage, translate, translateDocument } from "./i18n";
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
const waterIntro = document.querySelector<HTMLElement>(".water-intro")!;
const playback = document.querySelector<HTMLButtonElement>("#playback")!;
const playbackLabel = playback.querySelector("span")!;
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
const languagePicker = document.querySelector<HTMLSelectElement>("#language")!;
const languageCapsule = languagePicker.closest("label")!;
const motion = window.matchMedia("(prefers-reduced-motion: reduce)");
const debug = new URLSearchParams(location.search).has("debug");
const lines: string[] = [];
const events = new AbortController();
let instrument: InstrumentState = { count: 0, selected: 0, frequency: 0, notesPlayed: 0, demoPlaying: false };
let lastPlucked = false;
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
  audioUnavailable: !window.crossOriginIsolated,
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
  harmonyDemo.textContent = demo ? messages.stopDemo : messages.demo;
  const frequency = gesture.drawing ? gesture.previewFrequency : instrument.frequency;
  const name = noteName(frequency);
  harmonyNote.textContent = name;
  harmonyNote.setAttribute("aria-label", translate(gesture.drawing ? "drawPitch" : "selectedPitch", { pitch: pitchLabel(frequency) }));
  const pitchClass = frequency > 0 && Math.abs(centsFromNote(frequency)) < 1 ? ((midiOf(frequency) % 12) + 12) % 12 : -1;
  for (const tone of harmonyNotes.children) {
    (tone as HTMLElement).dataset.active = String(Number((tone as HTMLElement).dataset.pitch) === pitchClass);
  }
  const message = session.state.phase === "failed" ? messages.afterReload
    : session.state.phase === "loading" ? messages.preparing
    : !ready ? messages.pressPlay
    : gesture.drawing ? frequency > 0 ? translate("drawnPitch", { pitch: pitchLabel(frequency) }) : messages.drawLonger
    : demo ? messages.demoFeedback
    : instrument.count === 0 ? messages.drawFeedback
    : instrument.count < 3 ? messages.moreStrings
    : messages.playOwn;
  if (harmonyFeedback.textContent !== message) harmonyFeedback.textContent = message;
}

function showHarmony(): void {
  const harmony = harmonies[harmonyIndex];
  harmonyChord.textContent = harmony.chord;
  harmonyDescription.textContent = messages[harmony.hint];
  harmonyNotes.replaceChildren(...harmony.notes.map((pitch) => {
    const tone = document.createElement("span");
    tone.className = "harmony-tone";
    tone.dataset.pitch = String(pitch);
    tone.textContent = messages.noteNames[pitch];
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
  instrumentHint.textContent = session.state.phase === "failed" ? messages.afterReload
    : session.state.phase === "loading" ? messages.loading
    : !ready ? messages.pressPlay : messages.keyboard;
  if (!ready) pointerSession.cancel();
  updateHarmony();
}

function renderSelection(): void {
  const description = instrument.count === 0 ? messages.empty : translate("selection", {
    count: numbers.format(instrument.count), selected: numbers.format(instrument.selected), pitch: pitchLabel(instrument.frequency),
  });
  const message = lastPlucked ? translate("played", { selection: description }) : description;
  if (selection.textContent !== message) selection.textContent = message;
}

function updateInstrument(state: InstrumentState): void {
  lastPlucked = state.notesPlayed > instrument.notesPlayed;
  if (instrument.count === 0 && state.count > 0) waterIntro.toggleAttribute("data-played", true);
  const seeded = instrument.count === 0 && state.count > 0 && document.activeElement === harmonySeed;
  instrument = state;
  renderSelection();
  updateInstrumentControls();
  if (seeded) harmonyDemo.focus();
}

function renderPlayback(state: Readonly<PlaybackState>): void {
  const loading = state.phase === "loading";
  const failed = state.phase === "failed";
  loadingScreen.hidden = state.curtain === "hidden";
  loadingScreen.setAttribute("aria-hidden", String(state.curtain !== "visible"));
  loadingScreen.dataset.state = state.curtain === "leaving" ? "leaving" : "loading";
  loadingCaption.textContent = state.slow ? messages.slowCaption : messages.preparing;
  announce(state.announcement ? messages[state.announcement] : "", state.visibleAnnouncement);
  retry.hidden = !failed;
  if (failed && document.activeElement === playback) retry.focus();
  playback.hidden = failed;
  playback.dataset.phase = state.phase;
  playback.setAttribute("aria-disabled", String(loading));
  const action = loading ? messages.busy : state.phase === "playing" ? messages.pause : messages.play;
  // The button shows only an icon. The same word names it and serves as its tooltip.
  playbackLabel.textContent = action;
  playback.title = action;
  canvas.inert = state.phase !== "playing";
  updateInstrumentControls();
}

function updateGesture(state: GestureState): void {
  gesture = state;
  pointerSession.observe(state);
  updateHarmony();
}

playback.addEventListener("click", () => session.toggle(), { signal: events.signal });

canvas.addEventListener("pointerdown", (event) => {
  if (event.button === 0 && canPlayInstrument()) waterIntro.toggleAttribute("data-played", true);
}, { signal: events.signal });

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

function renderLanguage(): void {
  languagePicker.value = locale;
  translateDocument(languagePicker.selectedOptions[0].dir);
  // On the label: a title on the select would repeat its name as a description.
  languageCapsule.title = messages.language;
  help.hidden = false;
  canvas.removeAttribute("lang");
  renderSelection();
  showHarmony();
  pointerSession.observe(gesture);
}

languagePicker.addEventListener("change", async () => {
  try {
    if (!await setLanguage(languagePicker.value) || events.signal.aborted) return;
  } catch (error) {
    if (events.signal.aborted) return;
    languagePicker.value = locale;
    note(`language load error: ${error}`);
    announce(messages.languageError);
    return;
  }
  try { localStorage.setItem(languagePicker.name, locale); } catch { /* Use the selection for this visit. */ }
  renderLanguage();
  renderPlayback(session.state);
}, { signal: events.signal });

async function start(): Promise<void> {
  await setLanguage(document.documentElement.lang).catch(error => note(`language load error: ${error}`));
  if (events.signal.aborted) return;
  languageCapsule.hidden = false;
  instrumentControls.hidden = false;
  renderLanguage();
  session.start();
}
void start();
