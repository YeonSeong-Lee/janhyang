import { expect, test, type Page } from "@playwright/test";
import { moduleSource } from "./module-source";
import type { createPlaybackSession, PlaybackState } from "../src/playback-session";

declare global {
  interface Window {
    playbackHarness: {
      session: ReturnType<typeof createPlaybackSession>;
      state: Readonly<PlaybackState>;
      changes: Readonly<PlaybackState>[];
      loads: number;
      plays: number;
      pauses: number;
      cleanups: number;
      errors: number;
      signal?: AbortSignal;
      finish(reloading?: boolean): void;
      reject(): void;
    };
  }
}

async function setup(page: Page, reducedMotion = false): Promise<void> {
  await page.clock.install();
  await page.evaluate(async ({ source, reducedMotion }) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { createPlaybackSession } = await import(url) as typeof import("../src/playback-session");
    URL.revokeObjectURL(url);
    const session = createPlaybackSession({
      reducedMotion, audioNotice: "",
      load: (signal) => {
        const h = window.playbackHarness;
        h.loads++;
        h.signal = signal;
        return new Promise((resolve, reject) => {
          h.finish = (reloading) => resolve(reloading ? undefined : {
            play: () => { h.plays++; }, pause: () => { h.pauses++; }, cleanup: () => { h.cleanups++; },
            stopGesture() {}, setHarmony() {}, harmonyStrings() {}, playPhrase() {}, createString() {}, selectString() {}, pluckString() {},
          });
          h.reject = () => reject(new Error("test load failure"));
        });
      },
      changed: (state) => { window.playbackHarness.state = state; window.playbackHarness.changes.push(state); },
      failed: () => { window.playbackHarness.errors++; },
    });
    window.playbackHarness = { session, state: session.state, changes: [], loads: 0, plays: 0, pauses: 0,
      cleanups: 0, errors: 0, finish() {}, reject() {} };
    session.start();
  }, { source: await moduleSource("playback-session"), reducedMotion });
}

test("slow loading becomes playable before its curtain fades and never re-announces loading", async ({ page }) => {
  await setup(page);
  await page.evaluate(() => { window.playbackHarness.session.toggle(); window.playbackHarness.session.start(); });
  await page.clock.fastForward(10000);
  expect(await page.evaluate(() => window.playbackHarness.state.slow)).toBe(true);
  await page.evaluate(() => window.playbackHarness.finish());
  expect(await page.evaluate(() => ({ ready: window.playbackHarness.session.canPlay, state: window.playbackHarness.state,
    loads: window.playbackHarness.loads, plays: window.playbackHarness.plays }))).toMatchObject({
      ready: true, loads: 1, plays: 1, state: { phase: "playing", curtain: "leaving", slow: false },
    });
  await page.clock.fastForward(20000);
  expect(await page.evaluate(() => window.playbackHarness.state)).toMatchObject({ phase: "playing", curtain: "hidden", slow: false });
});

test("an early failure cancels both loading timers and cannot restart accidentally", async ({ page }) => {
  await setup(page);
  await page.evaluate(() => window.playbackHarness.reject());
  await page.clock.fastForward(20000);
  await page.evaluate(() => { window.playbackHarness.session.toggle(); window.playbackHarness.session.start(); });
  expect(await page.evaluate(() => ({ state: window.playbackHarness.state, errors: window.playbackHarness.errors,
    loads: window.playbackHarness.loads, plays: window.playbackHarness.plays }))).toMatchObject({
      state: { phase: "failed", curtain: "hidden", slow: false }, errors: 1, loads: 1, plays: 0,
    });
});

test("early readiness cancels the slow loading notice", async ({ page }) => {
  await setup(page);
  await page.evaluate(() => window.playbackHarness.finish());
  await page.clock.fastForward(20000);
  expect(await page.evaluate(() => window.playbackHarness.changes.some((state) => state.slow))).toBe(false);
  expect(await page.evaluate(() => window.playbackHarness.state.phase)).toBe("playing");
});

test("disposal cancels the pending curtain fade", async ({ page }) => {
  await setup(page);
  await page.evaluate(() => { window.playbackHarness.finish(); });
  await page.evaluate(() => window.playbackHarness.session.dispose());
  const changes = await page.evaluate(() => window.playbackHarness.changes.length);
  await page.clock.fastForward(20000);
  expect(await page.evaluate(() => window.playbackHarness.changes.length)).toBe(changes);
  expect(await page.evaluate(() => window.playbackHarness.cleanups)).toBe(1);
});

for (const completion of ["resolve", "reject"] as const) {
  test(`disposal ignores a late ${completion} and cleans up a late player`, async ({ page }) => {
    await setup(page);
    await page.evaluate(() => window.playbackHarness.session.dispose());
    await page.evaluate((completion) => {
      if (completion === "resolve") window.playbackHarness.finish();
      else window.playbackHarness.reject();
    }, completion);
    await page.clock.fastForward(20000);
    expect(await page.evaluate(() => ({ phase: window.playbackHarness.state.phase, plays: window.playbackHarness.plays,
      cleanups: window.playbackHarness.cleanups, errors: window.playbackHarness.errors,
      aborted: window.playbackHarness.signal?.aborted }))).toEqual({
        phase: "disposed", plays: 0, cleanups: completion === "resolve" ? 1 : 0, errors: 0, aborted: true,
      });
  });
}

test("reduced motion defers loading and a preference change during loading wins over autoplay", async ({ page }) => {
  await setup(page, true);
  expect(await page.evaluate(() => window.playbackHarness.loads)).toBe(0);
  await page.evaluate(() => {
    const h = window.playbackHarness;
    h.session.toggle();
    h.session.setReducedMotion(false);
    h.session.setReducedMotion(true);
    h.finish();
  });
  expect(await page.evaluate(() => ({ state: window.playbackHarness.state, plays: window.playbackHarness.plays,
    pauses: window.playbackHarness.pauses }))).toMatchObject({ state: { phase: "paused", curtain: "hidden" }, plays: 0, pauses: 1 });
  await page.evaluate(() => window.playbackHarness.session.setReducedMotion(false));
  expect(await page.evaluate(() => window.playbackHarness.session.canPlay)).toBe(false);
  await page.evaluate(() => window.playbackHarness.session.toggle());
  expect(await page.evaluate(() => window.playbackHarness.plays)).toBe(1);
});

test("bfcache retention preserves an in-flight load and the ready player", async ({ page }) => {
  await setup(page);
  await page.evaluate(() => { window.playbackHarness.session.dispose(true); window.playbackHarness.finish(); });
  await page.clock.fastForward(400);
  await page.evaluate(() => window.playbackHarness.session.dispose(true));
  expect(await page.evaluate(() => ({ ready: window.playbackHarness.session.canPlay, cleanups: window.playbackHarness.cleanups })))
    .toEqual({ ready: true, cleanups: 0 });
  await page.evaluate(() => {
    window.playbackHarness.session.dispose();
    window.playbackHarness.session.dispose();
    window.playbackHarness.session.toggle();
  });
  expect(await page.evaluate(() => ({ phase: window.playbackHarness.state.phase, cleanups: window.playbackHarness.cleanups,
    plays: window.playbackHarness.plays }))).toEqual({ phase: "disposed", cleanups: 1, plays: 1 });
});

test("an isolation reload leaves the loading scene until the document is disposed", async ({ page }) => {
  await setup(page);
  await page.evaluate(() => window.playbackHarness.finish(true));
  expect(await page.evaluate(() => window.playbackHarness.state)).toMatchObject({ phase: "loading", curtain: "visible" });
  await page.evaluate(() => window.playbackHarness.session.dispose());
  await page.clock.fastForward(20000);
  expect(await page.evaluate(() => window.playbackHarness.state)).toMatchObject({ phase: "disposed", curtain: "hidden", slow: false });
});
