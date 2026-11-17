import { expect, test } from "@playwright/test";

test("the phrase ends on time when rendering falls behind its note intervals", async ({ page }) => {
  await page.addInitScript(() => {
    const clock = { delay: 0, delayedFrames: 0 };
    (window as unknown as { phraseTestClock: typeof clock }).phraseTestClock = clock;
    const request = window.requestAnimationFrame.bind(window);
    const cancel = window.cancelAnimationFrame.bind(window);
    const pending = new Map<number, { timer: number; frame?: number }>();
    let serial = 0;
    window.requestAnimationFrame = (callback) => {
      const id = ++serial;
      const task: { timer: number; frame?: number } = { timer: 0 };
      if (clock.delay > 0) clock.delayedFrames++;
      task.timer = window.setTimeout(() => {
        task.frame = request((time) => { pending.delete(id); callback(time); });
      }, clock.delay);
      pending.set(id, task);
      return id;
    };
    window.cancelAnimationFrame = (id) => {
      const task = pending.get(id);
      if (!task) return;
      clearTimeout(task.timer);
      if (task.frame !== undefined) cancel(task.frame);
      pending.delete(id);
    };
  });
  await page.goto("/");
  await page.getByRole("button", { name: "어울리는 현 3개 놓기" }).click();
  await expect(page.locator("#selection")).toContainText("전체 3개");
  const demo = page.locator("#harmony-demo");
  await demo.focus();
  // Isolate the frame clock after the signed file's initial splash.
  await page.waitForTimeout(2500);
  await page.evaluate(() => {
    (window as unknown as { phraseTestClock: { delay: number } }).phraseTestClock.delay = 1500;
  });
  await page.waitForFunction(() =>
    (window as unknown as { phraseTestClock: { delayedFrames: number } }).phraseTestClock.delayedFrames > 0,
  undefined, { polling: 20 });
  await page.keyboard.press("Enter");
  await expect(demo).toHaveAttribute("aria-pressed", "true");
  await expect(demo).toHaveAttribute("aria-pressed", "false", { timeout: 10000 });
});
