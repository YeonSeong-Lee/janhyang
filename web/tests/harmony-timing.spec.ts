import { expect, test } from "@playwright/test";

test("a render-time gap ends the phrase without replaying stale notes", async ({ page }) => {
  await page.addInitScript(() => {
    const clock: { frozenTime?: number } = {};
    (window as unknown as { phraseTestClock: typeof clock }).phraseTestClock = clock;
    const request = window.requestAnimationFrame.bind(window);
    window.requestAnimationFrame = (callback) => request((time) => callback(clock.frozenTime ?? time));
  });
  await page.goto("/");
  await page.locator("summary").click();
  await page.getByRole("button", { name: "어울리는 현 3개 놓기" }).click();
  const demo = page.locator("#harmony-demo");
  await demo.click();
  await expect(demo).toHaveAttribute("aria-pressed", "true");
  // The first played note confirms the scene clock is running, including
  // after the signed export's splash. Keep the real renderer pumping so
  // its worker can accept a frame even on software-rendered CI.
  await expect(page.locator("#selection")).toContainText("선택한 현을 튕겼습니다");
  await page.evaluate(() => {
    (window as unknown as { phraseTestClock: { frozenTime?: number } }).phraseTestClock.frozenTime = performance.now() + 6000;
  });
  // Advance beyond the phrase, then freeze its clock. A scheduler that
  // discards the late frame's overshoot would stay playing indefinitely.
  await expect(demo).toHaveAttribute("aria-pressed", "false");
});
