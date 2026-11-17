import { noteName } from "./harmony";
import type { GestureState } from "./player";
import "./drag-guide.css";

/** A visual companion to Rive's gesture, never a second pitch or input engine. */
export function createDragGuide(canvas: HTMLCanvasElement, enabled: () => boolean) {
  const root = document.querySelector<HTMLElement>("#drag-guide")!;
  const caption = document.querySelector<HTMLElement>("#drag-caption")!;
  const note = document.querySelector<HTMLElement>("#drag-note")!;
  const hint = document.querySelector<HTMLElement>("#gesture-hint")!;
  const line = document.querySelector<SVGLineElement>("#guide-line")!;
  const target = document.querySelector<SVGCircleElement>("#guide-target")!;
  const events = new AbortController();
  let pointer: { id: number; touch: boolean; startX: number; startY: number; x: number; y: number } | undefined;
  let gesture: GestureState = { cursor: "crosshair", drawing: false, previewFrequency: 0 };

  function cancel(): void {
    pointer = undefined;
    root.dataset.visible = "false";
  }

  function render(): void {
    if (!enabled()) {
      cancel();
      return;
    }
    if (!pointer) return;
    const { x, y, startX, startY, touch } = pointer;
    const length = Math.hypot(x - startX, y - startY);
    const holding = gesture.cursor === "grabbing";
    // A tap should make a ripple without flashing an instruction.
    const visible = holding || (gesture.drawing && length >= 6);
    root.dataset.visible = String(visible);
    if (!visible) return;

    const frequency = gesture.previewFrequency;
    note.textContent = !holding && frequency > 0 ? noteName(frequency) : "";
    hint.textContent = holding ? "당겼다가 놓아보세요"
      : frequency > 0 ? "놓으면 이 음으로 울려요" : "조금 더 길게 그어보세요";

    const bounds = canvas.getBoundingClientRect();
    // Rive uses A3 (220 Hz) for a string one viewport high. Derive the
    // visual target from its actual tuned frequency, without re-snapping it.
    const targetLength = frequency > 0 ? bounds.height * 220 / frequency : 40;
    const targetX = startX + (x - startX) / Math.max(length, 1) * targetLength;
    const targetY = startY + (y - startY) / Math.max(length, 1) * targetLength;
    const targetVisible = !holding && targetX >= bounds.left + 10 && targetX <= bounds.right - 10
      && targetY >= bounds.top + 10 && targetY <= bounds.bottom - 10;
    root.dataset.target = String(targetVisible);
    root.dataset.aligned = String(frequency > 0 && Math.abs(targetLength - length) < 12);
    if (targetVisible) {
      line.setAttribute("x1", String(x));
      line.setAttribute("y1", String(y));
      line.setAttribute("x2", String(targetX));
      line.setAttribute("y2", String(targetY));
      target.setAttribute("cx", String(targetX));
      target.setAttribute("cy", String(targetY));
    }

    // Put touch guidance above the finger and keep the whole caption in view.
    const box = caption.getBoundingClientRect();
    const left = Math.max(16, Math.min(x + (touch ? -box.width / 2 : 18), innerWidth - box.width - 16));
    const gap = touch ? 54 : 32;
    // If the right edge moves the label back over a downward stroke, use
    // the empty space below it instead of painting text across the string.
    const below = !touch && y > startY && left < x;
    const preferredTop = below ? y + gap : y - box.height - gap;
    const fallbackTop = below ? y - box.height - gap : y + gap;
    const top = Math.max(16, Math.min(preferredTop < 16 || preferredTop + box.height > innerHeight - 16 ? fallbackTop : preferredTop,
      innerHeight - box.height - 16));
    caption.style.transform = `translate3d(${left}px, ${top}px, 0)`;
  }

  canvas.addEventListener("pointerdown", (event) => {
    if (!enabled() || pointer || event.button !== 0) return;
    pointer = { id: event.pointerId, touch: event.pointerType !== "mouse",
      startX: event.clientX, startY: event.clientY, x: event.clientX, y: event.clientY };
    gesture = { cursor: "crosshair", drawing: false, previewFrequency: 0 };
  }, { signal: events.signal });
  window.addEventListener("pointermove", (event) => {
    if (event.pointerId !== pointer?.id) return;
    pointer.x = event.clientX;
    pointer.y = event.clientY;
    render();
  }, { signal: events.signal });
  const release = (event: PointerEvent) => {
    if (event.pointerId === pointer?.id) cancel();
  };
  window.addEventListener("pointerup", release, { signal: events.signal });
  window.addEventListener("pointercancel", release, { signal: events.signal });
  canvas.addEventListener("lostpointercapture", release, { signal: events.signal });
  window.addEventListener("blur", cancel, { signal: events.signal });
  window.addEventListener("resize", cancel, { signal: events.signal });
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) cancel();
  }, { signal: events.signal });

  return {
    update(state: GestureState) {
      gesture = state;
      // Rive's previous release may arrive after the next native down.
      // Its state controls what is shown, never ownership of the new hand:
      // only native release/cancellation or an explicit control ends that.
      render();
    },
    cancel,
    cleanup() { cancel(); events.abort(); },
  };
}
