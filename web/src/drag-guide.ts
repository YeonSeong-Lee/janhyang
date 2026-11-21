import { messages, translate } from "./i18n";
import { noteName, pitchLabel, referenceFrequency } from "./harmony";
import type { GestureState } from "./player";
import type { PointerPosition } from "./pointer-session";
import "./drag-guide.css";

/** A visual companion to Rive's gesture, never a second pitch or input engine. */
export function createDragGuide(canvas: HTMLCanvasElement, referenceHarmony: () => number | null) {
  const root = document.querySelector<HTMLElement>("#drag-guide")!;
  const caption = document.querySelector<HTMLElement>("#drag-caption")!;
  const note = document.querySelector<HTMLElement>("#drag-note")!;
  const hint = document.querySelector<HTMLElement>("#gesture-hint")!;
  const line = document.querySelector<SVGLineElement>("#guide-line")!;
  const target = document.querySelector<SVGCircleElement>("#guide-target")!;
  function render(pointer: PointerPosition | undefined, gesture: GestureState): void {
    if (!pointer) {
      root.dataset.visible = "false";
      return;
    }
    const { x, y, startX, startY, touch } = pointer;
    const length = Math.hypot(x - startX, y - startY);
    const holding = gesture.cursor === "grabbing";
    // A tap should make a ripple without flashing an instruction.
    const visible = holding || (gesture.drawing && length >= 6);
    root.dataset.visible = String(visible);
    if (!visible) return;

    const frequency = gesture.previewFrequency;
    const harmony = referenceHarmony();
    const reference = harmony === null ? 0 : referenceFrequency(frequency, harmony);
    note.textContent = !holding && frequency > 0 ? pitchLabel(frequency) : "";
    hint.textContent = holding ? messages.hold
      : frequency > 0 ? reference > 0 ? translate("guideRef", { note: noteName(reference) }) : messages.sameLength
      : messages.drawLonger;

    const bounds = canvas.getBoundingClientRect();
    // Rive's actual pitch follows length continuously. The chord reference
    // marks a suggested length; it neither moves the endpoint nor tunes it.
    const targetLength = reference > 0 ? bounds.height * 220 / reference : 40;
    const targetX = startX + (x - startX) / Math.max(length, 1) * targetLength;
    const targetY = startY + (y - startY) / Math.max(length, 1) * targetLength;
    const targetVisible = harmony !== null && !holding && targetX >= bounds.left + 10 && targetX <= bounds.right - 10
      && targetY >= bounds.top + 10 && targetY <= bounds.bottom - 10;
    root.dataset.target = String(targetVisible);
    root.dataset.aligned = String(reference > 0 && Math.abs(1200 * Math.log2(frequency / reference)) < 5);
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

  return { render };
}
