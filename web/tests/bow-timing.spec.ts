import { expect, test } from "@playwright/test";

test("a button stroke starts and ends even when a frame exceeds its duration", async ({ page }) => {
  await page.addInitScript(() => {
    const clock = { delay: 0, delayedFrames: 0 };
    (window as unknown as { bowTestClock: typeof clock }).bowTestClock = clock;
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
  await page.getByRole("button", { name: "활로 켜기", exact: true }).click();
  await page.getByRole("button", { name: "연습 현 놓기" }).click();
  await expect(page.locator("#selection")).toContainText("전체 4개");
  await page.getByRole("button", { name: "한 활 연주", exact: true }).focus();
  // Let the signed file's splash finish before isolating the frame clock.
  await page.waitForTimeout(2500);
  await page.evaluate(() => {
    (window as unknown as { bowTestClock: { delay: number } }).bowTestClock.delay = 1500;
  });
  await page.waitForFunction(() =>
    (window as unknown as { bowTestClock: { delayedFrames: number } }).bowTestClock.delayedFrames > 0,
  undefined, { polling: 20 });
  await page.keyboard.press("Enter");
  await expect(page.locator("#stage")).toHaveCSS("cursor", "grabbing");
  await expect(page.locator("#bow-studio")).toHaveAttribute("data-sounding", "true");
  await expect(page.locator("#bow-studio")).toHaveAttribute("data-sounding", "false", { timeout: 5000 });
});
