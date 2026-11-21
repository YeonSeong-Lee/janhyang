import { defineConfig } from "vite";
import { localeHtml } from "./locale-html.ts";

// The file makes its own sound on an audio thread, and a browser shares
// memory with threads only on a page served with these two headers.
const isolation = {
  "Cross-Origin-Opener-Policy": "same-origin",
  "Cross-Origin-Embedder-Policy": "require-corp",
  "Cross-Origin-Resource-Policy": "same-origin",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
};

export default defineConfig({
  plugins: [localeHtml()],
  // Relative, so the same build works at a domain root and under a
  // GitHub Pages project path.
  base: "./",
  server: { headers: isolation },
  preview: { headers: isolation },
});
