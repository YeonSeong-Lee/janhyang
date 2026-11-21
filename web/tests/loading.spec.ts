import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

test("the introduction is visible before the entry script finishes loading", async ({ page }) => {
  let finishBootstrap!: () => void;
  const gate = new Promise<void>((resolve) => { finishBootstrap = resolve; });
  await page.route("**/assets/index-*.js", async (route) => {
    await gate;
    await route.continue();
  });
  try {
    await page.goto("/", { waitUntil: "commit" });
    await expect(page.getByRole("heading", { name: "당신의 손끝에서, 첫 울림이 시작됩니다." })).toBeVisible();
    await expect(page.getByRole("button", { name: "재생", exact: true })).toBeHidden();
    await expect(page.locator("#loading-screen")).toHaveCSS("position", "fixed");
    finishBootstrap();
    await expect(page.getByRole("button", { name: "일시정지", exact: true })).toBeEnabled();
    await expect(page.locator("#loading-screen")).toBeHidden();
  } finally {
    finishBootstrap();
  }
});

for (const viewport of [{ width: 1280, height: 800 }, { width: 320, height: 568 }, { width: 740, height: 360 }]) {
  test(`the loading introduction fits and remains accessible at ${viewport.width} × ${viewport.height}`, async ({ page }, testInfo) => {
    let finishLoading!: () => void;
    const gate = new Promise<void>((resolve) => { finishLoading = resolve; });
    await page.route("**/janhyang.riv", async (route) => {
      await gate;
      await route.continue();
    });
    try {
      await page.setViewportSize(viewport);
      await page.goto("/");
      await expect(page.locator("#loading-screen")).toBeVisible();
      await expect(page.getByRole("button", { name: "준비 중…", exact: true })).toBeDisabled();
      for (const selector of [".loading-name", ".loading-water", "#loading-title", ".loading-description", "#loading-caption"]) {
        const bounds = await page.locator(selector).boundingBox();
        expect(bounds).not.toBeNull();
        expect(bounds!.x).toBeGreaterThanOrEqual(0);
        expect(bounds!.y).toBeGreaterThanOrEqual(0);
        expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(viewport.width);
        // The introduction leaves room for the help and playback controls.
        expect(bounds!.y + bounds!.height).toBeLessThanOrEqual(viewport.height - 64);
      }
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(viewport.width);
      const accessibility = await new AxeBuilder({ page }).analyze();
      expect(accessibility.violations).toEqual([]);
      await page.locator(".loading-water").evaluate((element) => {
        for (const animation of element.getAnimations({ subtree: true })) {
          animation.pause();
          animation.currentTime = 2800;
        }
      });
      await page.screenshot({ path: testInfo.outputPath("loading.png") });
      await page.getByText("사용 안내", { exact: true }).click();
      await expect(page.locator("#instructions")).toBeVisible();
    } finally {
      finishLoading();
    }
  });
}

test("reduced motion keeps the loading illustration still and preserves keyboard focus", async ({ page, browserName }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  let finishLoading!: () => void;
  const gate = new Promise<void>((resolve) => { finishLoading = resolve; });
  await page.route("**/janhyang.riv", async (route) => {
    await gate;
    await route.continue();
  });
  try {
    await page.goto("/");
    await expect(page.locator("#loading-screen")).toBeHidden();
    // Option-Tab includes buttons with macOS WebKit's default keyboard navigation.
    await page.keyboard.press(browserName === "webkit" && process.platform === "darwin" ? "Alt+Tab" : "Tab");
    const playback = page.locator("#playback");
    await expect(playback).toBeFocused();
    await page.keyboard.press("Enter");
    const scene = page.locator("#loading-screen");
    await expect(scene).toBeVisible();
    expect(await scene.evaluate((element) => element.getAnimations({ subtree: true }).length)).toBe(0);
    await expect(playback).toBeFocused();
    // Changing the preference during a request must also leave the scene still.
    const motion = await page.evaluateHandle(() => matchMedia("(prefers-reduced-motion: reduce)"));
    // WebKit can update CSS before it delivers the change to existing media queries.
    const prefersLessMotion = () => motion.evaluate(query => query.matches);
    await page.emulateMedia({ reducedMotion: "no-preference" });
    await expect.poll(prefersLessMotion).toBe(false);
    await expect.poll(() => scene.evaluate((element) => element.getAnimations({ subtree: true }).length)).toBeGreaterThan(0);
    await page.emulateMedia({ reducedMotion: "reduce" });
    await expect.poll(prefersLessMotion).toBe(true);
    expect(await scene.evaluate((element) => element.getAnimations({ subtree: true }).length)).toBe(0);
    await expect(page.locator("#status")).toHaveText("수면을 준비하고 있습니다…");
    finishLoading();
    await expect(scene).toBeHidden();
    await expect(playback).toHaveText("재생");
    await expect(playback).toBeFocused();
    await expect(page.locator("#status")).toContainText("움직임을 멈췄습니다");
  } finally {
    finishLoading();
  }
});
