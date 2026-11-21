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
