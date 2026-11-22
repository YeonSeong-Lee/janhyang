import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

test("intro ripples travel during playback and rest after the first touch or with reduced motion", async ({ page }) => {
  await page.goto("/");
  const playback = page.locator("#playback");
  const ripples = page.locator(".water-ripples");
  const crest = ripples.locator(":scope > :first-child");
  const position = () => crest.evaluate(el => getComputedStyle(el).transform);
  const resting = () => ripples.evaluate(el => el.getAnimations({ subtree: true }).every(a => a.playState === "paused"));

  await expect(playback).toHaveAttribute("data-phase", "playing");
  const start = await position();
  await expect.poll(position).not.toBe(start);
  await playback.click();
  await expect.poll(resting).toBe(true);
  await playback.click();
  await expect.poll(resting).toBe(false);
  await page.locator("#stage").click({ position: { x: 60, y: 100 } });
  await expect(page.locator(".water-intro")).toHaveCSS("opacity", "0");
  await expect.poll(resting).toBe(true);

  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.reload();
  await expect(playback).toHaveAttribute("data-phase", "idle");
  const still = await position();
  await playback.click();
  await expect(playback).toHaveAttribute("data-phase", "playing");
  await expect.poll(resting).toBe(true);
  expect(await position()).toBe(still);
});

for (const viewport of [{ width: 1280, height: 800 }, { width: 360, height: 740 }, { width: 740, height: 360 }]) {
  test(`instrument controls remain accessible at ${viewport.width} × ${viewport.height}`, async ({ page }) => {
    await page.setViewportSize(viewport);
    await page.goto("/");
    await expect(page.getByRole("button", { name: "일시정지", exact: true })).toBeEnabled();
    const help = page.locator(".controls summary");
    const closedPosition = await help.boundingBox();
    await help.click();
    expect(await help.boundingBox()).toEqual(closedPosition);
    await page.getByRole("button", { name: "현 만들기", exact: true }).click();
    await expect(page.locator("#selection")).toContainText("전체 1개");
    const results = await new AxeBuilder({ page }).analyze();
    expect(results.violations).toEqual([]);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(viewport.width);
    for (const id of ["string-length", "create-string", "previous-string", "next-string", "pluck-strength", "pluck-string", "playback"]) {
      const control = page.locator(`#${id}`);
      await control.scrollIntoViewIfNeeded();
      const bounds = await control.boundingBox();
      expect(bounds!.height).toBeGreaterThanOrEqual(44);
      expect(bounds!.x).toBeGreaterThanOrEqual(0);
      expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(viewport.width);
      expect(bounds!.y).toBeGreaterThanOrEqual(0);
      expect(bounds!.y + bounds!.height).toBeLessThanOrEqual(viewport.height);
    }
  });
}

test("the controls keep their places between pause and play", async ({ page }) => {
  await page.goto("/");
  const pause = page.getByRole("button", { name: "일시정지", exact: true });
  await expect(pause).toBeEnabled();
  const places = () => page.locator("#playback, .controls summary, .language-picker")
    .evaluateAll(controls => controls.map(control => control.getBoundingClientRect().toJSON()));
  const playing = await places();
  await pause.click();
  await expect(page.getByRole("button", { name: "재생", exact: true })).toBeEnabled();
  expect(await places()).toEqual(playing);
});

test("borders snapped to device pixels leave the three controls one height", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  await expect(page.locator(".language-picker")).toBeVisible();
  // Emulated device pixel ratios don't snap borders. Zoom does, as a 150% display or Android would.
  await page.addStyleTag({ content: ".controls { zoom: 1.5; }" });
  const heights = await page.locator("#playback, .controls summary, .language-picker")
    .evaluateAll(controls => controls.map(control => control.getBoundingClientRect().height));
  for (const height of heights) expect(height).toBeCloseTo(heights[0], 1);
});

test("enlarged text scales play with its neighbours, and icon-only controls stay round", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.setViewportSize({ width: 1280, height: 700 });
  await page.goto("/");
  await expect(page.locator(".language-picker")).toBeVisible();
  await page.addStyleTag({ content: ":root { font-size: 200%; }" });
  const bounds = (selector: string) => page.locator(selector).evaluate(element => element.getBoundingClientRect().toJSON());
  const play = await bounds("#playback");
  expect(play.height).toBeCloseTo((await bounds(".language-picker")).height, 0);
  expect(play.width).toBeCloseTo(play.height, 0);
  // A narrow row needs the room for the help label, the only text left in it.
  await page.setViewportSize({ width: 320, height: 700 });
  for (const selector of ["#playback", ".language-picker"]) {
    const { width, height } = await bounds(selector);
    expect(width, selector).toBeCloseTo(44, 0);
    expect(height, selector).toBeCloseTo(44, 0);
  }
});

test("smaller text leaves the 44px capsules fully rounded", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.setViewportSize({ width: 320, height: 700 });
  await page.goto("/");
  await expect(page.locator(".language-picker")).toBeVisible();
  await page.addStyleTag({ content: ":root { font-size: 75%; }" });
  const shapes = await page.locator("#playback, .controls summary, .language-picker").evaluateAll(controls => controls.map(control => ({
    radius: parseFloat(getComputedStyle(control).borderTopLeftRadius),
    half: control.getBoundingClientRect().height / 2,
  })));
  for (const { radius, half } of shapes) expect(radius).toBeGreaterThanOrEqual(half - .5);
});

// Both sides of the breakpoint where the language name gives way to its icon.
for (const width of [320, 576, 577, 1280]) {
  test(`the whole language capsule is the native select at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 700 });
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.goto("/");
    const capsule = page.locator(".language-picker");
    for (const language of ["ko", "ar"]) {
      await page.locator("#language").selectOption(language);
      await expect(page.locator("html")).toHaveAttribute("lang", language);
      // WebKit only focuses a select when its label is clicked, so every point must hit the select itself.
      const hits = await capsule.evaluate(element => {
        const { x, y, width, height } = element.getBoundingClientRect();
        return [2, width / 4, width / 2, width * 3 / 4, width - 2]
          .map(offset => document.elementFromPoint(x + offset, y + height / 2)?.id);
      });
      expect(hits, language).toEqual(Array(5).fill("language"));
      const target = await page.locator("#language").boundingBox();
      expect(target!.width).toBeGreaterThanOrEqual(44);
      expect(target!.height).toBeGreaterThanOrEqual(44);
    }
  });
}
