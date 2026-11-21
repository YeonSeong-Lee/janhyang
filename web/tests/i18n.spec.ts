import { readdirSync, readFileSync } from "node:fs";
import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";
import type english from "../src/locales/en.json";

const directory = new URL("../src/locales/", import.meta.url);
const catalogs = new Map(readdirSync(directory).filter(file => file.endsWith(".json")).map(file =>
  [file.slice(0, -5), JSON.parse(readFileSync(new URL(file, directory), "utf8")) as typeof english] as const));
const placeholders = (value: string) => (value.match(/\{\w+\}/g) ?? []).sort();

test("every catalog has all messages, notes and interpolation fields", () => {
  const reference = catalogs.get("en")!;
  for (const [tag, copy] of catalogs) {
    expect(Object.keys(copy).sort(), tag).toEqual(Object.keys(reference).sort());
    for (const key of Object.keys(reference) as (keyof typeof english)[]) {
      if (key === "noteNames") {
        expect(Object.keys(copy[key]).sort(), tag).toEqual(Object.keys(reference[key]).sort());
        expect(Object.values(copy[key]).every(note => note.trim()), tag).toBe(true);
      } else {
        expect(copy[key].trim(), `${tag}.${key}`).toBeTruthy();
        expect(placeholders(copy[key]), `${tag}.${key}`).toEqual(placeholders(reference[key]));
      }
    }
  }
});

test("the intro follows browser preferences before the app module arrives", async ({ page }) => {
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "languages", { value: ["eo", "zh-HK", "en"] });
    localStorage.setItem("janhyang:language", "obsolete");
  });
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  await page.route("**/assets/index-*.js", async route => { await gate; await route.continue(); });
  try {
    await page.goto("/", { waitUntil: "commit" });
    await expect(page.locator("html")).toHaveAttribute("lang", "zh-Hant");
    await expect(page.getByRole("heading", { name: catalogs.get("zh-Hant")!.intro })).toBeVisible();
  } finally { release(); }
  await expect(page.getByRole("button", { name: "暫停", exact: true })).toBeEnabled();
});

test("each advertised language translates the instrument without restarting it", async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 568 });
  await page.goto("/");
  await expect(page.locator("#playback")).toHaveText("일시정지");
  await page.locator("summary").click();
  await page.locator("#harmony-mood").selectOption("2");
  await page.locator("#harmony-seed").click();
  const picker = page.locator("#language");
  const tags = await picker.locator("option").evaluateAll(options => options.map(o => (o as HTMLOptionElement).value));
  expect(tags.sort()).toEqual([...catalogs.keys()].sort());
  for (const tag of tags) {
    const copy = catalogs.get(tag)!;
    await picker.selectOption(tag);
    await expect(page.locator("html")).toHaveAttribute("lang", tag);
    await expect(picker).toHaveAccessibleName(copy.language);
    await expect(page.locator("#stage")).toHaveAccessibleName(copy.canvas);
    await expect(page.locator("#playback")).toHaveText(copy.pause);
    await expect(page.locator("#harmony-description")).toHaveText(copy.warmHint);
    await expect(page.locator("#harmony-notes > span").first()).toHaveText(copy.noteNames[5]);
    await expect(page.locator("#selection")).toContainText("C4");
    await expect(page.locator("#harmony-seed")).toBeHidden();
    expect(await page.evaluate(() => document.documentElement.scrollWidth), tag).toBe(320);
  }
  await picker.selectOption("ar");
  await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
  expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]);
  await picker.selectOption("es");
  await page.locator("#previous-string").click();
  await expect(page.locator("#selection")).toContainText("Cuerda 2 de 3");
  await page.locator("#pluck-string").click();
  await expect(page.locator("#selection")).toContainText("Has pulsado la cuerda");
  await page.reload();
  await expect(picker).toHaveValue("es");
  await expect(page.locator("#playback")).toHaveText("Pausa");
});

for (const [preference, expected, dir] of [
  ["zh-SG", "zh-Hans", "ltr"], ["zh-Hans-TW", "zh-Hans", "ltr"], ["pa-PK", "pa-Arab", "rtl"],
  ["ja-JP", "ja", "ltr"], ["eo", "en", "ltr"],
]) {
  test(`negotiates ${preference} without storage`, async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.addInitScript(preference => {
      Object.defineProperty(navigator, "languages", { value: [preference] });
      Object.defineProperty(window, "localStorage", { get() { throw new Error("storage blocked"); } });
    }, preference);
    await page.goto("/");
    await expect(page.locator("#language")).toHaveValue(expected);
    await expect(page.locator("html")).toHaveAttribute("dir", dir);
    await expect(page.locator("#status")).toHaveText(catalogs.get(expected)!.reduced);
    await page.locator("#language").selectOption("fr");
    await expect(page.locator("#status")).toHaveText(catalogs.get("fr")!.reduced);
  });
}

test("drawing, failures and a subsequent language choice use the active catalog", async ({ page }) => {
  await page.goto("/");
  await page.locator("#language").selectOption("es");
  await expect(page.locator("#playback")).toHaveText("Pausa");
  await page.mouse.move(60, 120);
  await page.mouse.down();
  await page.mouse.move(330, 120, { steps: 8 });
  await expect(page.locator("#drag-note")).toHaveText(/Cerca de .+ · \d+,\d Hz/);
  await expect(page.locator("#gesture-hint")).toContainText("Referencia");
  await page.mouse.up();
  await page.route("**/janhyang.riv", route => route.abort());
  await page.reload();
  await expect(page.locator("#status")).toHaveText(catalogs.get("es")!.loadError);
  await page.locator("#language").selectOption("ja");
  await expect(page.locator("#status")).toHaveText(catalogs.get("ja")!.loadError);
  await expect(page.getByRole("button", { name: "再読み込み" })).toBeVisible();
});

test("an unavailable catalog falls back, and selecting it again can recover", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  const path = "**/assets/ko-*.json";
  await page.route(path, route => route.abort());
  await page.goto("/");
  const picker = page.getByRole("combobox", { name: "Language", exact: true });
  await expect(picker).toHaveValue("en");
  await picker.selectOption("ko");
  await expect(page.locator("#status")).toHaveText(catalogs.get("en")!.languageError);
  await expect(picker).toHaveValue("en");
  await page.unroute(path);
  await picker.selectOption("ko");
  await expect(page.locator("#status")).toHaveText(catalogs.get("ko")!.reduced);
});

test("a late translation cannot overwrite the latest choice", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  const picker = page.locator("#language");
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  const path = "**/assets/es-*.json";
  await page.route(path, async route => { await gate; await route.continue(); });
  try {
    const downloaded = page.waitForResponse(path);
    await picker.selectOption("es");
    await picker.selectOption("ja");
    await expect(page.locator("html")).toHaveAttribute("lang", "ja");
    release();
    await (await downloaded).finished();
    await expect(page.getByRole("combobox", { name: "言語", exact: true })).toHaveValue("ja");
    await expect(page.locator("#status")).toHaveText(catalogs.get("ja")!.reduced);
  } finally { release(); }
});
