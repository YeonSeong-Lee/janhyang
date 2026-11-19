import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

async function ready(page: Page): Promise<void> {
  await page.goto("/");
  await expect(page.getByRole("button", { name: "일시정지", exact: true })).toBeEnabled();
}

test("drawing preserves off-chord pitches and small changes instead of snapping to the guide", async ({ page }) => {
  await ready(page);
  await page.locator("summary").click();
  await page.getByLabel("참고할 화음").selectOption("1");
  await page.locator("summary").click();
  const guide = page.locator("#drag-guide");
  await expect(page.locator("#harmony-panel")).toBeHidden();
  await expect(guide).toHaveCSS("opacity", "0");
  await page.mouse.move(60, 120);
  await page.mouse.down();
  await page.mouse.move(80, 120);
  await expect(guide).toHaveAttribute("data-visible", "true");
  await expect(page.locator("#gesture-hint")).toContainText("조금 더 길게");
  await page.mouse.move(330, 120, { steps: 10 });
  await expect(page.locator("#gesture-hint")).toContainText("참고 C5");
  await expect(page.locator("#drag-note")).toHaveText("D5 부근 · 586.7 Hz");
  const target = Number(await page.locator("#guide-target").getAttribute("cx"));
  expect(target).toBeGreaterThan(350);
  // Moving only one pixel changes the actual pitch within the same semitone.
  // The optional C5 marker stays put and does not attract the endpoint.
  await page.mouse.move(331, 120);
  await expect(page.locator("#drag-note")).toHaveText("D5 부근 · 584.5 Hz");
  expect(Number(await page.locator("#guide-target").getAttribute("cx"))).toBeCloseTo(target);
  const preview = await page.locator("#drag-note").textContent();
  await page.mouse.up();
  await expect(guide).toHaveCSS("opacity", "0");
  await expect(page.locator("#selection")).toContainText(`전체 1개 중 1번째 현 · ${preview}`);
  await expect(page.locator("#harmony-notes [data-active=true]")).toHaveCount(0);
  await page.mouse.move(60, 210);
  await page.mouse.down();
  await page.mouse.move(80, 210);
  await page.mouse.up();
  await expect(page.locator("#selection")).toContainText("전체 1개");
  await page.mouse.move(60, 290);
  await page.mouse.down();
  await page.mouse.move(330, 290, { steps: 10 });
  await expect(guide).toHaveAttribute("data-visible", "true");
  await page.keyboard.press("Escape");
  await page.mouse.up();
  await expect(guide).toHaveCSS("opacity", "0");
  await expect(page.locator("#selection")).toContainText("전체 1개");
});

test("changing the reference leaves existing starter strings at their original pitches", async ({ page }) => {
  await ready(page);
  await page.locator("summary").click();
  const seed = page.getByRole("button", { name: "어울리는 현 3개 놓기" });
  await seed.focus();
  await page.keyboard.press("Enter");
  await expect(page.locator("#selection")).toContainText("전체 3개 중 3번째 현 · E4");
  const demo = page.getByRole("button", { name: "짧은 연주 듣기" });
  await expect(demo).toBeFocused();
  for (const value of ["1", "2", "0"]) {
    await page.getByLabel("참고할 화음").selectOption(value);
    await page.getByRole("button", { name: "이전 현", exact: true }).click();
    await expect(page.locator("#selection")).toContainText("전체 3개 중 2번째 현 · C4");
    await page.getByRole("button", { name: "다음 현", exact: true }).click();
    await expect(page.locator("#selection")).toContainText("전체 3개 중 3번째 현 · E4");
  }
  await expect(seed).toBeHidden();
  await page.getByRole("button", { name: "이 현 들어보기" }).click();
  await expect(page.locator("#selection")).toContainText("선택한 현을 튕겼습니다");
});

test("reference choices and hiding the guide never change a drawn string's pitch", async ({ page }) => {
  await ready(page);
  for (const [index, mood] of ["0", "1", "2"].entries()) {
    await page.locator("summary").click();
    await page.getByLabel("참고할 화음").selectOption(mood);
    const showGuide = page.getByRole("checkbox", { name: "화음 길이 안내 표시" });
    if (index === 1) {
      await showGuide.focus();
      await page.keyboard.press("Space");
      await expect(showGuide).not.toBeChecked();
    }
    await page.locator("summary").click();
    await page.mouse.move(60, 100 + index * 100);
    await page.mouse.down();
    await page.mouse.move(300, 100 + index * 100, { steps: 8 });
    await expect(page.locator("#drag-note")).toHaveText("E5 부근 · 660.0 Hz");
    await expect(page.locator("#drag-guide")).toHaveAttribute("data-target", index === 0 ? "true" : "false");
    await page.mouse.up();
    await expect(page.locator("#selection")).toContainText(`전체 ${index + 1}개 중 ${index + 1}번째 현 · E5 부근 · 660.0 Hz`);
  }
  await page.locator("summary").click();
  await page.getByRole("button", { name: "이전 현", exact: true }).click();
  await expect(page.locator("#selection")).toContainText("전체 3개 중 2번째 현 · E5 부근 · 660.0 Hz");
  await page.getByRole("button", { name: "이전 현", exact: true }).click();
  await expect(page.locator("#selection")).toContainText("전체 3개 중 1번째 현 · E5 부근 · 660.0 Hz");
});

test("the phrase finishes on its own", async ({ page }) => {
  await ready(page);
  await page.locator("summary").click();
  await page.getByRole("button", { name: "어울리는 현 3개 놓기" }).click();
  const demo = page.locator("#harmony-demo");
  await demo.click();
  await expect(demo).toHaveAttribute("aria-pressed", "true");
  await expect(page.locator("#selection")).toContainText("선택한 현을 튕겼습니다");
  await page.getByLabel("참고할 화음").selectOption("2");
  await expect(demo).toHaveAttribute("aria-pressed", "true");
  await expect(demo).toHaveAttribute("aria-pressed", "false", { timeout: 12000 });
});

test("the phrase restarts after Escape and direct interaction cancels it", async ({ page }) => {
  await ready(page);
  await page.locator("summary").click();
  await page.getByRole("button", { name: "어울리는 현 3개 놓기" }).click();
  const demo = page.locator("#harmony-demo");
  await demo.click();
  await expect(demo).toHaveAttribute("aria-pressed", "true");
  await page.keyboard.press("Escape");
  await expect(demo).toHaveAttribute("aria-pressed", "false");
  await demo.click();
  await expect(demo).toHaveAttribute("aria-pressed", "true");
  await page.mouse.click(40, 100);
  await expect(demo).toHaveAttribute("aria-pressed", "false");
});

test("pause cancels the phrase and resume does not restart it", async ({ page }) => {
  await ready(page);
  await page.locator("summary").click();
  await page.getByRole("button", { name: "어울리는 현 3개 놓기" }).click();
  const demo = page.locator("#harmony-demo");
  await demo.click();
  await expect(demo).toHaveAttribute("aria-pressed", "true");
  await page.getByRole("button", { name: "일시정지", exact: true }).click();
  await expect(demo).toHaveAttribute("aria-pressed", "false");
  await expect(demo).toBeDisabled();
  await page.getByRole("button", { name: "재생", exact: true }).click();
  await expect(demo).toHaveAttribute("aria-pressed", "false");
});

for (const viewport of [{ width: 1280, height: 800 }, { width: 320, height: 568 }, { width: 740, height: 360 }]) {
  test(`harmony controls and starter strings are reachable at ${viewport.width} × ${viewport.height}`, async ({ page }, testInfo) => {
    await page.setViewportSize(viewport);
    await ready(page);
    await page.locator("summary").click();
    const accessibility = await new AxeBuilder({ page }).analyze();
    expect(accessibility.violations).toEqual([]);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(viewport.width);
    for (const id of ["harmony-mood", "harmony-seed", "harmony-demo"]) {
      const control = page.locator(`#${id}`);
      await control.scrollIntoViewIfNeeded();
      const bounds = await control.boundingBox();
      expect(bounds!.height).toBeGreaterThanOrEqual(44);
      expect(bounds!.x).toBeGreaterThanOrEqual(0);
      expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(viewport.width);
      expect(bounds!.y).toBeGreaterThanOrEqual(0);
      expect(bounds!.y + bounds!.height).toBeLessThanOrEqual(viewport.height);
    }
    await page.getByRole("button", { name: "어울리는 현 3개 놓기" }).click();
    await expect(page.locator("#selection")).toContainText("전체 3개");
    await page.locator("summary").click();
    await expect(page.locator("#harmony-panel")).toBeHidden();
    const landscape = viewport.width >= 600 && viewport.height <= 500;
    const x = (landscape ? viewport.width - 368 : viewport.width) / 2;
    const bottom = landscape ? viewport.height - 76 : Math.max(184, Math.min(viewport.height * 0.48, viewport.height - 340));
    for (let i = 0; i < 3; i++) {
      const y = 84 + (bottom - 84) * i / 2;
      await page.mouse.move(x, y);
      await expect(page.locator("#stage")).toHaveCSS("cursor", "grab");
      await page.mouse.down();
      await expect(page.locator("#selection")).toContainText(`전체 3개 중 ${i + 1}번째 현`);
      await page.mouse.up();
    }
    await page.mouse.move(20, 50);
    // The signed export has a short Rive splash. This delay is only for the
    // review image; all interaction assertions above wait on actual state.
    await page.waitForTimeout(3000);
    await page.screenshot({ path: testInfo.outputPath("harmony.png") });
    await page.locator("summary").click();
    await expect(page.locator("#harmony-panel")).toBeVisible();
  });
}
