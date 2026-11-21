import type { Player } from "./player";

export interface PlaybackState {
  phase: "idle" | "loading" | "playing" | "paused" | "failed" | "disposed";
  curtain: "visible" | "leaving" | "hidden";
  slow: boolean;
  announcement: string;
  visibleAnnouncement: boolean;
}

/** Owns playback intent, asynchronous settlement, and loading feedback timers. */
export function createPlaybackSession(options: {
  load(signal: AbortSignal): Promise<Player | undefined>;
  reducedMotion: boolean;
  audioNotice: string;
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
    announcement: "움직임 줄이기 설정이 켜져 있습니다. 재생을 누르면 현과 파문이 움직입니다.",
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
      announcement: "수면을 준비하고 있습니다…", visibleAnnouncement: false });
    slowTimer = window.setTimeout(() => update({ slow: true,
      announcement: "준비가 조금 길어지고 있어요. 연결 상태에 따라 시간이 걸릴 수 있습니다." }), 10000);
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
        announcement: paused ? "움직임을 멈췄습니다. 재생을 누르면 현과 파문이 움직입니다."
          : options.audioNotice || "수면을 준비했습니다. 연주할 수 있습니다.",
        visibleAnnouncement: paused || Boolean(options.audioNotice) });
      // Readiness is already published; the remaining timer is visual only.
      if (state.curtain === "leaving") exitTimer = window.setTimeout(() => update({ curtain: "hidden" }), 400);
    } catch (error) {
      if (lifetime.signal.aborted) return;
      clearTimers();
      player?.cleanup();
      player = undefined;
      options.failed(error);
      update({ phase: "failed", curtain: "hidden", slow: false,
        announcement: "화면을 불러오지 못했습니다. 연결을 확인한 뒤 다시 불러와 주세요.", visibleAnnouncement: true });
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
      update({ phase: paused ? "paused" : "playing", announcement: paused ? "" : options.audioNotice,
        visibleAnnouncement: !paused && Boolean(options.audioNotice) });
    },
    setReducedMotion(reduce: boolean): void {
      reducedMotion = reduce;
      if (!reduce || state.phase === "failed" || lifetime.signal.aborted) return;
      paused = true;
      player?.pause();
      if (state.phase === "loading") return;
      window.clearTimeout(exitTimer);
      update({ phase: player ? "paused" : "idle", curtain: "hidden",
        announcement: "움직임 줄이기 설정에 따라 멈췄습니다. 재생을 누르면 다시 시작합니다.", visibleAnnouncement: true });
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
