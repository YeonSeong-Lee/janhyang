import { Fit, Layout, Rive, RuntimeLoader } from "@rive-app/webgl2-threads";
import wasmURL from "@rive-app/webgl2-threads/rive.wasm?url";
import fallbackURL from "@rive-app/webgl2-threads/rive_fallback.wasm?url";
import threadsURL from "@rive-app/webgl2-threads/rive_threads.wasm?url";

export interface Player {
  play(): void;
  pause(): void;
  cleanup(): void;
}

export async function createPlayer(
  canvas: HTMLCanvasElement,
  note: (message: string) => void,
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
      rive.volume = 1;
      rive.play();
      note("play");
    },
    pause() {
      rive.volume = 0;
      // Let the runtime finish its paused frame and reset its clock, so
      // resuming does not advance by the time spent paused.
      rive.pause();
      note("pause");
    },
    cleanup() {
      observer.disconnect();
      resolution.removeEventListener("change", watchResolution);
      cancelAnimationFrame(resizeFrame);
      rive.cleanup();
    },
  };
}
