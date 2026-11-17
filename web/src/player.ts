import { Fit, Layout, Rive, RuntimeLoader } from "@rive-app/webgl2-threads";
import wasmURL from "@rive-app/webgl2-threads/rive.wasm?url";
import fallbackURL from "@rive-app/webgl2-threads/rive_fallback.wasm?url";
import threadsURL from "@rive-app/webgl2-threads/rive_threads.wasm?url";

export interface InstrumentState {
  count: number;
  selected: number;
  frequency: number;
  notesPlayed: number;
}

export interface Player {
  play(): void;
  pause(): void;
  setBowMode(enabled: boolean): void;
  createString(length: number): void;
  selectString(direction: -1 | 1): void;
  pluckString(strength: number): void;
  cleanup(): void;
}

export async function createPlayer(
  canvas: HTMLCanvasElement,
  note: (message: string) => void,
  onInstrumentChange: (state: InstrumentState) => void,
  onGestureChange: (cursor: string, contacts: number) => void = () => {},
): Promise<Player> {
  // Bundle the installed binaries, including the compatibility fallback.
  RuntimeLoader.setWasmUrl(wasmURL);
  RuntimeLoader.setWasmFallbackUrl(fallbackURL);
  RuntimeLoader.setWasmThreadsUrl(threadsURL);

  const rive = await new Promise<Rive>((resolve, reject) => {
    let instance: Rive;
    const timeout = setTimeout(() => {
      instance.cleanup();
      reject(new Error("Rive loading timed out"));
    }, 30000);
    try {
      instance = new Rive({
        src: `${import.meta.env.BASE_URL}janhyang.riv`,
        canvas,
        autoplay: false,
        stateMachines: "State Machine 1",
        autoBind: true,
        tabIndex: -1,
        enableGPUCanvas: true,
        layout: new Layout({ fit: Fit.Layout }),
        onLoad: () => {
          clearTimeout(timeout);
          resolve(instance);
        },
        onLoadError: (event) => {
          clearTimeout(timeout);
          instance.cleanup();
          reject(new Error(String(event.data)));
        },
      });
    } catch (error) {
      clearTimeout(timeout);
      reject(error);
    }
  });

  const model = rive.viewModelInstance;
  const count = model?.number("stringCount");
  const selected = model?.number("selectedString");
  const frequency = model?.number("frequency");
  const notesPlayed = model?.number("notesPlayed");
  const lengthFraction = model?.number("lengthFraction");
  const pluckStrength = model?.number("pluckStrength");
  const create = model?.trigger("createString");
  const previous = model?.trigger("previousString");
  const next = model?.trigger("nextString");
  const pluck = model?.trigger("pluckString");
  const bowMode = model?.boolean("bowMode");
  const cursor = model?.string("cursor");
  const cancelGesture = model?.number("cancelGesture");
  const bowContacts = model?.number("bowContacts");
  if (!count || !selected || !frequency || !notesPlayed || !lengthFraction || !pluckStrength ||
      !create || !previous || !next || !pluck || !bowMode || !cursor || !cancelGesture || !bowContacts) {
    rive.cleanup();
    throw new Error("The instrument's controls are missing from the Rive file");
  }
  const stateProperties = [count, selected, frequency, notesPlayed];
  let previousState: InstrumentState | undefined;
  const emitState = () => {
    const state = { count: count.value, selected: selected.value, frequency: frequency.value, notesPlayed: notesPlayed.value };
    // Several properties can change in one Rive advance. Announce that
    // resulting state once, after the runtime has applied the whole action.
    if (previousState && Object.keys(state).every((key) =>
      state[key as keyof InstrumentState] === previousState![key as keyof InstrumentState])) return;
    previousState = state;
    onInstrumentChange(state);
  };
  for (const property of stateProperties) property.on(emitState);
  emitState();

  let playing = false;
  const events = new AbortController();
  const emitGesture = () => {
    const value = playing ? cursor.value : "default";
    canvas.style.cursor = ["grab", "grabbing", "crosshair"].includes(value) ? value : "default";
    onGestureChange(value, playing ? bowContacts.value : 0);
  };
  const cancel = () => {
    cancelGesture.value++;
    canvas.style.cursor = playing ? (bowMode.value ? "grab" : "crosshair") : "default";
  };
  cursor.on(emitGesture);
  bowContacts.on(emitGesture);
  window.addEventListener("blur", cancel, { signal: events.signal });
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) cancel();
  }, { signal: events.signal });
  canvas.addEventListener("pointercancel", cancel, { signal: events.signal });

  let resizeFrame = 0;
  let resolution: MediaQueryList;

  function resize(): void {
    resizeFrame = 0;
    rive.resizeDrawingSurfaceToCanvas();
    note(`resized: ${canvas.width}x${canvas.height} @${devicePixelRatio}x`);
  }

  function scheduleResize(): void {
    if (!resizeFrame) resizeFrame = requestAnimationFrame(resize);
  }

  function watchResolution(): void {
    resolution?.removeEventListener("change", watchResolution);
    resolution = matchMedia(`(resolution: ${devicePixelRatio}dppx)`);
    resolution.addEventListener("change", watchResolution);
    scheduleResize();
  }

  const observer = new ResizeObserver(scheduleResize);
  observer.observe(canvas);
  resize();
  watchResolution();
  note(`loaded: artboard "${rive.activeArtboard}"`);
  note(`canvas: ${canvas.width}x${canvas.height} @${devicePixelRatio}x`);
  note(`isolated: ${window.crossOriginIsolated}`);

  return {
    play() {
      playing = true;
      rive.volume = 1;
      rive.play();
      emitGesture();
      note("play");
    },
    pause() {
      playing = false;
      cancel();
      rive.volume = 0;
      // Let the runtime finish its paused frame and reset its clock, so
      // resuming does not advance by the time spent paused.
      rive.pause();
      emitGesture();
      note("pause");
    },
    setBowMode(enabled) {
      cancel();
      bowMode.value = enabled;
    },
    createString(length) {
      lengthFraction.value = length;
      create.trigger();
    },
    selectString(direction) {
      (direction < 0 ? previous : next).trigger();
    },
    pluckString(strength) {
      pluckStrength.value = strength;
      pluck.trigger();
    },
    cleanup() {
      events.abort();
      cursor.off(emitGesture);
      bowContacts.off(emitGesture);
      for (const property of stateProperties) property.off(emitState);
      observer.disconnect();
      resolution.removeEventListener("change", watchResolution);
      cancelAnimationFrame(resizeFrame);
      rive.cleanup();
    },
  };
}
