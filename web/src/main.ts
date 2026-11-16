import { EventType, Fit, Layout, Rive } from "@rive-app/webgl2-threads";

// The page is only a frame for the canvas. Everything seen and heard is in
// the .riv file.
const canvas = document.getElementById("stage") as HTMLCanvasElement;
const report = document.getElementById("report") as HTMLPreElement;
const debug = new URLSearchParams(location.search).has("debug");
const lines: string[] = [];

function note(line: string): void {
  lines.push(line);
  if (debug) {
    report.hidden = false;
    report.textContent = lines.join("\n");
  }
  console.info(`[janhyang] ${line}`);
}

window.addEventListener("error", (event) => note(`error: ${event.message}`));
window.addEventListener("unhandledrejection", (event) => note(`rejection: ${String(event.reason)}`));

const rive = new Rive({
  src: `${import.meta.env.BASE_URL}janhyang.riv`,
  canvas,
  autoplay: true,
  enableGPUCanvas: true,
  layout: new Layout({ fit: Fit.Layout }),
  onLoad: () => {
    rive.resizeDrawingSurfaceToCanvas();
    note(`loaded: artboard "${rive.activeArtboard}"`);
    note(`state machines: ${JSON.stringify(rive.stateMachineNames)}`);
    note(`animations: ${JSON.stringify(rive.animationNames)}`);
    note(`playing: ${JSON.stringify(rive.playingStateMachineNames)} ${rive.isPlaying}`);
    note(`canvas: ${canvas.width}x${canvas.height} @${window.devicePixelRatio}x`);
    // The file's own sound needs threads, which a browser allows only on a
    // page served with cross origin isolation.
    note(`isolated: ${window.crossOriginIsolated}`);
  },
  onLoadError: (event) => note(`load error: ${JSON.stringify(event.data)}`),
});

rive.on(EventType.Play, (event) => note(`play: ${JSON.stringify(event.data)}`));
rive.on(EventType.Pause, (event) => note(`pause: ${JSON.stringify(event.data)}`));

window.addEventListener("resize", () => rive.resizeDrawingSurfaceToCanvas());
