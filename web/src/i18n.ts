import english from "./locales/en.json";

type Messages = typeof english;
type MessageKey = Exclude<keyof Messages, "noteNames">;
const files = import.meta.glob<string>(["./locales/*.json", "!./locales/en.json"], {
  eager: true, import: "default", query: "?url&no-inline",
});
const catalogs = new Map<string, Messages>([["en", english]]);
export let locale = "en";
export let messages = english;
export let numbers = new Intl.NumberFormat(locale);
export let frequencies = frequencyFormat(locale);

function frequencyFormat(language: string): Intl.NumberFormat {
  return new Intl.NumberFormat(language, { minimumFractionDigits: 1, maximumFractionDigits: 1, useGrouping: false });
}

// A slow download must never replace a more recent selection.
let request = 0;
export async function setLanguage(language: string): Promise<boolean> {
  const current = ++request;
  try {
    let catalog = catalogs.get(language);
    if (!catalog) {
      const response = await fetch(files[`./locales/${language}.json`]);
      if (!response.ok) throw new Error(`Language ${language}: HTTP ${response.status}`);
      catalog = await response.json() as Messages;
      catalogs.set(language, catalog);
    }
    if (current !== request) return false;
    locale = language;
    messages = catalog;
    numbers = new Intl.NumberFormat(locale);
    frequencies = frequencyFormat(locale);
    return true;
  } catch (error) {
    if (current !== request) return false;
    throw error;
  }
}

export function translate(key: MessageKey, values: Record<string, string> = {}): string {
  return messages[key].replace(/\{(\w+)\}/g, (_, name: string) =>
    document.documentElement.dir === "rtl" ? `\u2068${values[name]}\u2069` : values[name]);
}

export function translateDocument(direction: string): void {
  document.documentElement.lang = locale;
  document.documentElement.dir = direction;
  for (const element of document.querySelectorAll<HTMLElement>("[data-i18n]")) {
    element.textContent = messages[element.dataset.i18n as MessageKey];
  }
  for (const element of document.querySelectorAll<HTMLElement>("[data-i18n-label]")) {
    element.setAttribute("aria-label", messages[element.dataset.i18nLabel as MessageKey]);
  }
  document.title = `${messages.brand} — ${messages.tagline}`;
  document.querySelector<HTMLMetaElement>('meta[name="description"]')!.content = messages.description.replace(/\s+/g, " ");
  document.querySelector<HTMLMetaElement>('meta[name="application-name"]')!.content = messages.brand;
}
