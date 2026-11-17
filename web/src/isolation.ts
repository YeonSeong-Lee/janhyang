/** Prepare the header fallback for hosts such as GitHub Pages. */
export async function prepareIsolation(
  workerURL: URL,
  note: (message: string) => void,
): Promise<"ready" | "reloading"> {
  if (window.crossOriginIsolated) return "ready";
  if (!window.isSecureContext || !("serviceWorker" in navigator)) {
    note("isolation unavailable: audio threads need a secure, isolated page");
    return "ready";
  }

  try {
    const workers = navigator.serviceWorker;
    // An already controlled navigation has had its chance to gain isolation.
    // Never reload a live experience for a later worker update.
    if (workers.controller) return "ready";
    const reloadKey = `janhyang:coi-reloaded:${workerURL.pathname}`;
    if (sessionStorage.getItem(reloadKey)) return "ready";

    return await new Promise((resolve) => {
      let finished = false;
      const finish = (result: "ready" | "reloading") => {
        if (finished) return;
        finished = true;
        clearTimeout(timeout);
        workers.removeEventListener("controllerchange", onController);
        resolve(result);
      };
      const onController = () => {
        if (finished || workers.controller?.scriptURL !== workerURL.href) return;
        try {
          // A persistent guard is required before a document replaces itself.
          sessionStorage.setItem(reloadKey, "1");
          location.reload();
          finish("reloading");
        } catch (error) {
          note(`isolation reload skipped: ${String(error)}`);
          finish("ready");
        }
      };
      const timeout = setTimeout(() => {
        note("isolation worker timed out; continuing without audio threads");
        finish("ready");
      }, 4000);

      // Subscribe before registration to avoid losing a fast activation.
      workers.addEventListener("controllerchange", onController);
      try {
        workers.register(workerURL.href).then(onController, (error) => {
          note(`isolation worker unavailable: ${String(error)}`);
          finish("ready");
        });
      } catch (error) {
        note(`isolation worker unavailable: ${String(error)}`);
        finish("ready");
      }
    });
  } catch (error) {
    note(`isolation unavailable: ${String(error)}`);
    return "ready";
  }
}
