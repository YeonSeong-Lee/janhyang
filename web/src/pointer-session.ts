import type { GestureState } from "./player";

export interface PointerPosition {
  id: number;
  touch: boolean;
  startX: number;
  startY: number;
  x: number;
  y: number;
}

/** Native input owns the hand. Renderer observations only describe its picture. */
export function createPointerSession(canvas: HTMLCanvasElement, options: {
  enabled(): boolean;
  guideEnabled(): boolean;
  show(pointer: PointerPosition | undefined, gesture: GestureState): void;
  stop(): void;
}) {
  const events = new AbortController();
  let pointer: PointerPosition | undefined;
  let gesture: GestureState = { cursor: "crosshair", drawing: false, previewFrequency: 0 };
  let guideHidden = false;

  function render(): void {
    options.show(options.enabled() && options.guideEnabled() && !guideHidden ? pointer : undefined, gesture);
  }

  function release(): void {
    pointer = undefined;
    render();
  }

  function cancel(): void {
    release();
    options.stop();
  }

  canvas.addEventListener("pointerdown", (event) => {
    if (!options.enabled() || pointer) return;
    pointer = { id: event.pointerId, touch: event.pointerType !== "mouse",
      startX: event.clientX, startY: event.clientY, x: event.clientX, y: event.clientY };
    // Rive accepts non-primary buttons too; keep their cancellation owner,
    // while the visual guide remains reserved for the primary button.
    guideHidden = event.button !== 0 || !options.guideEnabled();
    gesture = { cursor: "crosshair", drawing: false, previewFrequency: 0 };
    render();
  }, { signal: events.signal });
  window.addEventListener("pointermove", (event) => {
    if (event.pointerId !== pointer?.id) return;
    pointer.x = event.clientX;
    pointer.y = event.clientY;
    render();
  }, { signal: events.signal });
  window.addEventListener("pointerup", (event) => {
    if (event.pointerId === pointer?.id) release();
  }, { signal: events.signal });
  const cancelOwner = (event: PointerEvent) => {
    if (event.pointerId === pointer?.id) cancel();
  };
  window.addEventListener("pointercancel", cancelOwner, { signal: events.signal });
  canvas.addEventListener("lostpointercapture", cancelOwner, { signal: events.signal });
  window.addEventListener("blur", cancel, { signal: events.signal });
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) cancel();
  }, { signal: events.signal });
  window.addEventListener("resize", () => {
    // A resize dismisses the caption, not the held string or its owner.
    guideHidden = true;
    render();
  }, { signal: events.signal });

  return {
    observe(state: GestureState) { gesture = state; render(); },
    cancel,
    cleanup() { events.abort(); release(); },
  };
}
