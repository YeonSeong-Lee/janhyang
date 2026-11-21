import type { Player } from "./player";

export interface PlaybackState {
  phase: "idle" | "loading" | "playing" | "paused" | "failed" | "disposed";
  curtain: "visible" | "leaving" | "hidden";
  slow: boolean;
  announcement: "" | "reduced" | "loading" | "slowNotice" | "paused" | "silent" | "ready" | "loadError" | "reducedPause";
  visibleAnnouncement: boolean;
}

/** Owns playback intent, asynchronous settlement, and loading feedback timers. */
export function createPlaybackSession(options: {
  load(signal: AbortSignal): Promise<Player | undefined>;
  reducedMotion: boolean;
  audioUnavailable: boolean;
  changed(state: Readonly<PlaybackState>): void;
  failed(error: unknown): void;
}) {
  const lifetime = new AbortController();
  let player: Player | undefined;
  let paused = options.reducedMotion;
  let reducedMotion = options.reducedMotion;
  let slowTimer: number | undefined;
  let exitTimer: number | undefined;
  let state: PlaybackState = {
    phase: "idle", curtain: "hidden", slow: false,
    announcement: "reduced",
    visibleAnnouncement: true,
  };

  function update(next: Partial<PlaybackState>): void {
    state = { ...state, ...next };
    options.changed(state);
  }

  function clearTimers(): void {
    window.clearTimeout(slowTimer);
    window.clearTimeout(exitTimer);
  }

  async function load(): Promise<void> {
    if (state.phase !== "idle") return;
    update({ phase: "loading", curtain: "visible", slow: false,
      announcement: "loading", visibleAnnouncement: false });
    slowTimer = window.setTimeout(() => update({ slow: true,
      announcement: "slowNotice" }), 10000);
    try {
      const loaded = await options.load(lifetime.signal);
      if (lifetime.signal.aborted) { loaded?.cleanup(); return; }
      // The isolation worker is replacing this document. Keep the curtain.
      if (!loaded) return;
      player = loaded;
      clearTimers();
      if (paused) player.pause();
      else player.play();
      update({ phase: paused ? "paused" : "playing", curtain: reducedMotion ? "hidden" : "leaving", slow: false,
        announcement: paused ? "paused"
          : options.audioUnavailable ? "silent" : "ready",
        visibleAnnouncement: paused || options.audioUnavailable });
      // Readiness is already published; the remaining timer is visual only.
      if (state.curtain === "leaving") exitTimer = window.setTimeout(() => update({ curtain: "hidden" }), 400);
    } catch (error) {
      if (lifetime.signal.aborted) return;
      clearTimers();
      player?.cleanup();
      player = undefined;
      options.failed(error);
      update({ phase: "failed", curtain: "hidden", slow: false,
        announcement: "loadError", visibleAnnouncement: true });
    }
  }

  return {
    get state(): Readonly<PlaybackState> { return state; },
    get player(): Player | undefined { return player; },
    get canPlay(): boolean { return state.phase === "playing"; },
    start(): void {
      if (state.phase !== "idle") return;
      if (paused) options.changed(state);
      else void load();
    },
    toggle(): void {
      if (["loading", "failed", "disposed"].includes(state.phase)) return;
      paused = !paused;
      if (!player) { void load(); return; }
      if (paused) player.pause();
      else player.play();
      update({ phase: paused ? "paused" : "playing", announcement: !paused && options.audioUnavailable ? "silent" : "",
        visibleAnnouncement: !paused && options.audioUnavailable });
    },
    setReducedMotion(reduce: boolean): void {
      reducedMotion = reduce;
      if (!reduce || state.phase === "failed" || lifetime.signal.aborted) return;
      paused = true;
      player?.pause();
      if (state.phase === "loading") return;
      window.clearTimeout(exitTimer);
      update({ phase: player ? "paused" : "idle", curtain: "hidden",
        announcement: "reducedPause", visibleAnnouncement: true });
    },
    dispose(persisted = false): void {
      // A bfcache entry keeps its player and intent; the runtime owns visibility.
      if (persisted || lifetime.signal.aborted) return;
      lifetime.abort();
      clearTimers();
      player?.cleanup();
      player = undefined;
      update({ phase: "disposed", curtain: "hidden", slow: false });
    },
  };
}
