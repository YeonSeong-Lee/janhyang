import { expect, test, type Page } from "@playwright/test";

async function ready(page: Page): Promise<void> {
  await page.goto("/");
  await expect(page.getByRole("button", { name: "일시정지", exact: true })).toBeEnabled();
}

for (const viewport of [{ width: 1280, height: 800, note: "E4" }, { width: 320, height: 568, note: "E5" }, { width: 740, height: 360, note: "A3" }]) {
  test(`guidance follows the drag and leaves the water clear at ${viewport.width} × ${viewport.height}`, async ({ page }, testInfo) => {
    await page.setViewportSize(viewport);
    await ready(page);
    const guide = page.locator("#drag-guide");
    await expect(guide).toHaveCSS("opacity", "0");
    await expect(page.locator("#harmony-panel")).toBeHidden();
    // Allow only the signed Rive splash to finish for the review images.
    await page.waitForTimeout(3000);
    await page.screenshot({ path: testInfo.outputPath("idle.png") });
    await page.mouse.click(30, 30);
    await expect(guide).toHaveAttribute("data-visible", "false");
    await expect(page.locator("#selection")).toContainText("아직 현이 없습니다");
    await page.mouse.move(viewport.width * .25, viewport.height * .28);
    await page.mouse.down();
    await page.mouse.move(viewport.width * .7, viewport.height * .48, { steps: 12 });
    await expect(guide).toHaveCSS("opacity", "1");
    await expect(page.locator("#drag-note")).toHaveText(viewport.note);
    const preview = await page.locator("#drag-note").textContent();
    const caption = await page.locator("#drag-caption").boundingBox();
    expect(caption!.x).toBeGreaterThanOrEqual(16);
    expect(caption!.x + caption!.width).toBeLessThanOrEqual(viewport.width - 16);
    expect(caption!.y).toBeGreaterThanOrEqual(16);
    expect(caption!.y + caption!.height).toBeLessThanOrEqual(viewport.height - 16);
    await expect(guide).toHaveAttribute("data-target", "true");
    expect(await page.evaluate(({ x, y }) => document.elementFromPoint(x, y)?.id,
      { x: caption!.x + 4, y: caption!.y + 4 })).toBe("stage");
    await page.screenshot({ path: testInfo.outputPath("drawing.png") });
    await page.mouse.up();
    await expect(guide).toHaveCSS("opacity", "0");
    await expect(page.locator("#selection")).toContainText(`전체 1개 중 1번째 현 · ${preview}`);

    // Near an edge, keep the caption readable and avoid inventing a target
    // by clamping a note's natural length to the screen boundary.
    await page.mouse.move(viewport.width - 35, 45);
    await page.mouse.down();
    await page.mouse.move(viewport.width - 8, 45, { steps: 4 });
    await expect(guide).toHaveAttribute("data-visible", "true");
    await expect(guide).toHaveAttribute("data-target", "false");
    const edge = await page.locator("#drag-caption").boundingBox();
    expect(edge!.x + edge!.width).toBeLessThanOrEqual(viewport.width - 16);
    expect(edge!.y).toBeGreaterThanOrEqual(16);
    await page.mouse.up();
    await expect(page.locator("#selection")).toContainText("전체 1개");
  });
}

test("touch guidance stays above the finger and survives a second finger releasing", async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const touch = await page.context().newCDPSession(page);
  await touch.send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 2 });
  await ready(page);
  // The signed splash also appears in the touch review image.
  await page.waitForTimeout(3000);
  await touch.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: 70, y: 300, id: 1 }] });
  await touch.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: 270, y: 300, id: 1 }] });
  const guide = page.locator("#drag-guide");
  await expect(guide).toHaveAttribute("data-visible", "true");
  await expect(page.locator("#drag-note")).toHaveText("A5");
  await page.screenshot({ path: testInfo.outputPath("touch.png") });
  const before = await page.locator("#drag-caption").boundingBox();
  expect(before!.y + before!.height).toBeLessThanOrEqual(246);
  await touch.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: 270, y: 300, id: 1 }, { x: 300, y: 500, id: 2 }] });
  // CDP touchEnd names the lifted points, not the fingers still touching.
  await touch.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [{ x: 300, y: 500, id: 2 }] });
  await expect(guide).toHaveAttribute("data-visible", "true");
  await touch.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: 250, y: 345, id: 1 }] });
  await expect.poll(async () => (await page.locator("#drag-caption").boundingBox())!.y).toBeGreaterThan(before!.y);
  await touch.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await expect(guide).toHaveCSS("opacity", "0");
  await expect(page.locator("#selection")).toContainText("전체 1개");
  await touch.detach();
});

test("cancel, blur, pause and opening help dismiss an unfinished guide without creating a string", async ({ page }) => {
  await ready(page);
  const guide = page.locator("#drag-guide");
  for (const action of ["escape", "blur", "pause", "help"]) {
    await page.mouse.move(60, 100);
    await page.mouse.down();
    await page.mouse.move(260, 150, { steps: 8 });
    await expect(guide).toHaveAttribute("data-visible", "true");
    if (action === "escape") await page.keyboard.press("Escape");
    if (action === "blur") await page.evaluate(() => window.dispatchEvent(new Event("blur")));
    if (action === "pause") {
      await page.locator("#playback").focus();
      await page.keyboard.press("Enter");
    }
    if (action === "help") {
      await page.locator("summary").focus();
      await page.keyboard.press("Enter");
    }
    await expect(guide).toHaveCSS("opacity", "0");
    await page.mouse.up();
    await expect(page.locator("#selection")).toContainText("아직 현이 없습니다");
    if (action === "pause") await page.getByRole("button", { name: "재생", exact: true }).click();
  }
});

test("reduced motion removes guide fading after the user starts playback", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  await page.getByRole("button", { name: "재생", exact: true }).click();
  await expect(page.getByRole("button", { name: "일시정지", exact: true })).toBeEnabled();
  await page.mouse.move(60, 100);
  await page.mouse.down();
  await page.mouse.move(260, 100, { steps: 8 });
  const guide = page.locator("#drag-guide");
  await expect(guide).toHaveCSS("opacity", "1");
  await expect(guide).toHaveCSS("transition-duration", "0s");
  await page.keyboard.press("Escape");
  await expect(guide).toHaveCSS("opacity", "0");
  await page.mouse.up();
});
