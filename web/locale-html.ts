import { readdirSync, readFileSync } from "node:fs";
import type { Plugin } from "vite";
import type english from "./src/locales/en.json";

function escapeHtml(text: string): string {
  return text.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
}

/** Keep the first paint and the JavaScript-disabled notice usable on a static host. */
export function localeHtml(): Plugin {
  const directory = new URL("./src/locales/", import.meta.url);
  return {
    name: "janhyang-locale-html",
    transformIndexHtml(html) {
      const catalogs = readdirSync(directory).filter(file => file.endsWith(".json")).map(file => ({
        tag: file.slice(0, -5),
        copy: JSON.parse(readFileSync(new URL(file, directory), "utf8")) as typeof english,
      })).sort((a, b) => a.copy.nativeName.localeCompare(b.copy.nativeName, "en"));
      const options: string[] = [];
      const notices: string[] = [];
      for (const { tag, copy } of catalogs) {
        const direction = ["ar", "fa", "he", "pa-Arab", "ur"].includes(tag) ? "rtl" : "ltr";
        const attributes = `lang="${tag}" dir="${direction}"`;
        const intro = (["brand", "intro", "description", "preparing", "tagline"] as const)
          .map(key => `data-${key}="${escapeHtml(copy[key])}"`).join(" ");
        options.push(`<option value="${tag}" ${attributes} ${intro}>${escapeHtml(copy.nativeName)}</option>`);
        notices.push(`<li ${attributes}><strong>${escapeHtml(copy.nativeName)}</strong> · ${escapeHtml(copy.enableJS)}</li>`);
      }
      return html.replace("<!-- language-options -->", () => options.join("\n"))
        .replace("<!-- language-notices -->", () => notices.join("\n"));
    },
  };
}
