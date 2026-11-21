import { expect, test } from "@playwright/test";
import { moduleSource } from "./module-source";
import type { GestureState } from "../src/player";
import type { createPointerSession, PointerPosition } from "../src/pointer-session";

declare global {
  interface Window {
    pointerHarness: {
      input: ReturnType<typeof createPointerSession>;
      pointer: PointerPosition | undefined;
      gesture: GestureState;
      stops: number;
      shown: number;
      enabled: boolean;
      guideEnabled: boolean;
      send(type: string, id: number, x?: number): void;
    };
  }
}

test.beforeEach(async ({ page }) => {
  await page.setContent("<canvas></canvas>");
  await page.evaluate(async (source) => {
    const url = URL.createObjectURL(new Blob([source], { type: "text/javascript" }));
    const { createPointerSession } = await import(url) as typeof import("../src/pointer-session");
    URL.revokeObjectURL(url);
    const canvas = document.querySelector("canvas")!;
    const input = createPointerSession(canvas, {
      enabled: () => window.pointerHarness.enabled,
      guideEnabled: () => window.pointerHarness.guideEnabled,
      show: (pointer, gesture) => {
        window.pointerHarness.pointer = pointer ? { ...pointer } : undefined;
        window.pointerHarness.gesture = gesture;
        window.pointerHarness.shown++;
      },
      stop: () => { window.pointerHarness.stops++; },
    });
    window.pointerHarness = { input, pointer: undefined,
      gesture: { cursor: "crosshair", drawing: false, previewFrequency: 0 },
      stops: 0, shown: 0, enabled: true, guideEnabled: true,
      send: (type, id, x = 100) => canvas.dispatchEvent(new PointerEvent(type,
        { bubbles: true, pointerId: id, pointerType: "touch", clientX: x, clientY: 100, button: 0 })),
    };
  }, await moduleSource("pointer-session"));
});

test("late renderer release never relinquishes the next native pointer", async ({ page }) => {
  const result = await page.evaluate(() => {
    const h = window.pointerHarness;
    h.send("pointerdown", 1);
    h.input.observe({ cursor: "grabbing", drawing: false, previewFrequency: 0 });
    h.send("pointerup", 1);
    h.send("pointerdown", 2);
    // Explicitly order the stale notification after the next native down.
    h.input.observe({ cursor: "crosshair", drawing: false, previewFrequency: 0 });
    h.send("lostpointercapture", 1);
    h.send("pointermove", 2, 280);
    h.input.observe({ cursor: "crosshair", drawing: true, previewFrequency: 440 });
    return { pointer: h.pointer, drawing: h.gesture.drawing, stops: h.stops };
  });
  expect(result.pointer).toMatchObject({ id: 2, startX: 100, x: 280 });
  expect(result.drawing).toBe(true);
  expect(result.stops).toBe(0);
});

test("only owner cancellation stops the engine, and release is not cancellation", async ({ page }) => {
  const result = await page.evaluate(() => {
    const h = window.pointerHarness;
    h.send("pointerdown", 1);
    h.send("pointerdown", 2);
    h.send("pointercancel", 2);
    h.send("pointerup", 2);
    const held = h.pointer?.id;
    h.send("pointerup", 1);
    const releasedStops = h.stops;
    h.send("pointerdown", 3);
    h.send("pointercancel", 3);
    h.input.observe({ cursor: "grabbing", drawing: false, previewFrequency: 0 });
    return { held, releasedStops, stops: h.stops, pointer: h.pointer };
  });
  expect(result).toEqual({ held: 1, releasedStops: 0, stops: 1, pointer: undefined });
});

test("resize dismisses guidance but retains the owner for a later cancellation", async ({ page }) => {
  const result = await page.evaluate(() => {
    const h = window.pointerHarness;
    h.send("pointerdown", 1);
    window.dispatchEvent(new Event("resize"));
    h.send("pointermove", 1, 220);
    h.input.observe({ cursor: "crosshair", drawing: true, previewFrequency: 440 });
    const dismissed = { pointer: h.pointer, stops: h.stops };
    h.send("lostpointercapture", 1);
    const cancelledStops = h.stops;
    h.send("pointerdown", 2);
    return { dismissed, cancelledStops, nextOwner: h.pointer?.id };
  });
  expect(result).toEqual({ dismissed: { pointer: undefined, stops: 0 }, cancelledStops: 1, nextOwner: 2 });
});

test("a non-primary button retains cancellation ownership without showing guidance", async ({ page }) => {
  const result = await page.evaluate(() => {
    const h = window.pointerHarness;
    document.querySelector("canvas")!.dispatchEvent(new PointerEvent("pointerdown",
      { bubbles: true, pointerId: 1, pointerType: "mouse", button: 2 }));
    h.input.observe({ cursor: "grabbing", drawing: false, previewFrequency: 0 });
    const hidden = h.pointer === undefined;
    h.send("lostpointercapture", 1);
    h.send("pointerdown", 2);
    return { hidden, stops: h.stops, nextOwner: h.pointer?.id };
  });
  expect(result).toEqual({ hidden: true, stops: 1, nextOwner: 2 });
});

test("help gating keeps input ownership and cleanup removes native listeners", async ({ page }) => {
  const result = await page.evaluate(() => {
    const h = window.pointerHarness;
    h.guideEnabled = false;
    h.send("pointerdown", 1);
    const hidden = h.pointer === undefined;
    h.send("pointercancel", 1);
    const stops = h.stops;
    h.input.cleanup();
    const shown = h.shown;
    window.dispatchEvent(new Event("blur"));
    h.send("pointerdown", 2);
    return { hidden, stops, afterCleanup: h.stops, furtherRenders: h.shown - shown };
  });
  expect(result).toEqual({ hidden: true, stops: 1, afterCleanup: 1, furtherRenders: 0 });
});
