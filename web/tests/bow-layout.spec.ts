import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

for (const viewport of [{ width: 1280, height: 800 }, { width: 360, height: 740 }, { width: 740, height: 360 }]) {
  test(`bow controls remain accessible at ${viewport.width} × ${viewport.height}`, async ({ page }) => {
    await page.setViewportSize(viewport);
    await page.goto("/");
    await page.getByRole("button", { name: "활로 켜기", exact: true }).click();
    await page.getByRole("button", { name: "연습 현 놓기" }).click();
    await expect(page.locator("#bow-note")).toHaveText("D4");
    // Signed Rive files display the account's two-second splash. Wait for
    // the actual surface before reviewing its composition and input area.
    await page.waitForTimeout(2500);
    const surfaceWidth = viewport.width >= 700 && viewport.height <= 560 ? viewport.width - 360 : viewport.width;
    await page.mouse.move(surfaceWidth * 0.425, viewport.height * 0.35);
    await page.mouse.down();
    await page.mouse.move(surfaceWidth * 0.48, viewport.height * 0.35, { steps: 15 });
    await expect(page.locator("#bow-studio")).toHaveAttribute("data-sounding", "true");
    await expect(page.locator("#stage")).toHaveCSS("cursor", "grabbing");
    // GPU submission can trail the view-model update; capture the settled
    // held bow rather than the pre-gesture surface.
    await page.waitForTimeout(300);
    await page.screenshot({ path: test.info().outputPath("bow-studio.png") });
    await page.mouse.up();
    const results = await new AxeBuilder({ page }).analyze();
    expect(results.violations).toEqual([]);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(viewport.width);
    for (const id of ["bow-pressure", "bow-stroke", "bow-mode", "playback"]) {
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
