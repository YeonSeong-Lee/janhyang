import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

for (const viewport of [{ width: 1280, height: 800 }, { width: 360, height: 740 }, { width: 740, height: 360 }]) {
  test(`instrument controls remain accessible at ${viewport.width} × ${viewport.height}`, async ({ page }) => {
    await page.setViewportSize(viewport);
    await page.goto("/");
    await expect(page.getByRole("button", { name: "일시정지", exact: true })).toBeEnabled();
    await page.getByText("사용 안내", { exact: true }).click();
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
