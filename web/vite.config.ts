import { defineConfig } from "vite";

export default defineConfig({
  // Relative, so the same build works at a domain root and under a
  // GitHub Pages project path.
  base: "./",
});
