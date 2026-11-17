import { expect, test, type Page } from "@playwright/test";

async function ready(page: Page): Promise<void> {
  await page.goto("/?debug");
  await expect(page.getByRole("button", { name: "일시정지", exact: true })).toBeEnabled();
  await expect(page.getByRole("button", { name: "활로 켜기", exact: true })).toBeVisible();
}

async function draw(page: Page, y: number, endX = 650): Promise<void> {
  await page.mouse.move(100, y);
  await page.mouse.down();
  await page.mouse.move(endX, y, { steps: 8 });
  await page.mouse.up();
}

test("a string advertises grab, confirms the hold and releases it", async ({ page }) => {
  await ready(page);
  await draw(page, 200);
  const canvas = page.locator("#stage");
  await page.mouse.move(300, 200);
  await expect(canvas).toHaveCSS("cursor", "grab");
  await expect(page.locator("#gesture-hint")).toContainText("누른 채 당기세요");
  await page.mouse.down();
  await expect(canvas).toHaveCSS("cursor", "grabbing");
  await page.mouse.move(300, 260, { steps: 8 });
  await expect(page.locator("#gesture-hint")).toContainText("현을 잡았어요");
  await page.mouse.up();
  await page.mouse.move(50, 500);
  await expect(canvas).toHaveCSS("cursor", "crosshair");
  await page.locator("summary").click();
  await expect(page.locator("#selection")).toContainText("전체 1개");
});

test("one bow contacts multiple strings without drawing another, then returns to drawing", async ({ page }) => {
  await ready(page);
  await draw(page, 200);
  await draw(page, 280, 500);
  const bow = page.getByRole("button", { name: "활로 켜기", exact: true });
  const canvas = page.locator("#stage");
  await bow.click();
  await expect(bow).toHaveAttribute("aria-pressed", "true");
  await page.getByRole("button", { name: "여러 현 함께 켜기" }).click();
  await page.mouse.move(300, 240);
  await expect(page.locator("#gesture-hint")).toContainText("2개의 현");
  await page.mouse.down();
  await expect(canvas).toHaveCSS("cursor", "grabbing");
  await page.mouse.move(300, 270, { steps: 16 });
  await page.mouse.move(300, 220, { steps: 16 });
  await expect(page.locator("#gesture-hint")).toContainText("2개의 현");
  await page.mouse.up();
  await expect(canvas).toHaveCSS("cursor", "grab");
  await bow.click();
  await expect(bow).toHaveAttribute("aria-pressed", "false");
  await draw(page, 400);
  await page.locator("summary").click();
  await expect(page.locator("#selection")).toContainText("전체 3개");
});

test("blur, pause and button actions cancel a held bow", async ({ page }) => {
  await ready(page);
  await draw(page, 200);
  await page.getByRole("button", { name: "활로 켜기", exact: true }).click();
  const canvas = page.locator("#stage");
  await page.mouse.move(300, 220);
  await page.mouse.down();
  await page.mouse.move(300, 240, { steps: 8 });
  await expect(canvas).toHaveCSS("cursor", "grabbing");
  await page.evaluate(() => window.dispatchEvent(new Event("blur")));
  await expect(canvas).toHaveCSS("cursor", "grab");
  await page.mouse.up();

  await page.mouse.down();
  await expect(canvas).toHaveCSS("cursor", "grabbing");
  // Keyboard activation must stop a gesture even with the mouse held down.
  await page.getByRole("button", { name: "일시정지", exact: true }).focus();
  await page.keyboard.press("Enter");
  await expect(canvas).toHaveJSProperty("inert", true);
  await expect(canvas).toHaveCSS("cursor", "default");
  await expect(page.getByRole("button", { name: "활로 켜기", exact: true })).toBeDisabled();
  await page.mouse.up();
  await page.keyboard.press("Enter");
  await page.mouse.move(300, 220);
  await expect(canvas).toHaveCSS("cursor", "grab");

  await page.locator("summary").click();
  await page.mouse.move(300, 220);
  await page.mouse.down();
  await expect(canvas).toHaveCSS("cursor", "grabbing");
  await page.getByRole("button", { name: "현 만들기", exact: true }).focus();
  await page.keyboard.press("Enter");
  await expect(canvas).toHaveCSS("cursor", "grab");
  await page.mouse.up();
  await expect(page.locator("#selection")).toContainText("전체 2개");
});

test("empty bow mode offers playable violin strings and pressure controls", async ({ page }) => {
  await ready(page);
  await page.getByRole("button", { name: "활로 켜기", exact: true }).click();
  const studio = page.locator("#bow-studio");
  await expect(studio).toBeVisible();
  await expect(page.getByRole("button", { name: "한 활 연주", exact: true })).toBeDisabled();
  await page.getByRole("button", { name: "연습 현 놓기" }).click();
  await expect(page.locator("#selection")).toContainText("전체 4개");
  await expect(page.getByRole("button", { name: "한 활 연주", exact: true })).toBeFocused();
  await expect(page.getByRole("button", { name: "연습 현 놓기" })).toBeHidden();
  await expect(page.locator("#bow-note")).toHaveText("D4");
  await page.getByRole("button", { name: "다음 연주 현" }).click();
  await expect(page.locator("#bow-note")).toHaveText("A4");
  const pressure = page.getByRole("slider", { name: "활의 압력" });
  await pressure.focus();
  await page.keyboard.press("End");
  await expect(pressure).toHaveValue("100");
  await expect(pressure).toHaveAttribute("aria-valuetext", "단단하게, 100%");
  await page.getByRole("button", { name: "한 활 연주", exact: true }).focus();
  await page.keyboard.press("Enter");
  await expect(studio).toHaveAttribute("data-sounding", "true");
  await expect(studio).toHaveAttribute("data-sounding", "false");
  await page.keyboard.press("Enter");
  await expect(studio).toHaveAttribute("data-sounding", "true");
  await page.keyboard.press("Escape");
  await expect(studio).toHaveAttribute("data-sounding", "false");
  await page.getByRole("button", { name: "활로 켜기", exact: true }).click();
  await expect(studio).toBeHidden();
  await expect(page.locator("#selection")).toContainText("전체 4개");
});

test("bow motion follows the hair and stopping the hand settles the feedback", async ({ page }) => {
  await ready(page);
  await draw(page, 200);
  await page.getByRole("button", { name: "활로 켜기", exact: true }).click();
  const studio = page.locator("#bow-studio");
  await page.mouse.move(240, 200);
  await page.mouse.down();
  // Along a horizontal string is perpendicular to its vertical bow.
  await page.mouse.move(450, 200, { steps: 10 });
  await expect(studio).toHaveAttribute("data-sounding", "false");
  await page.mouse.move(450, 280, { steps: 15 });
  await expect(studio).toHaveAttribute("data-sounding", "true");
  await expect(studio).toHaveAttribute("data-sounding", "false");
  await page.mouse.move(450, 200, { steps: 15 });
  await expect(studio).toHaveAttribute("data-sounding", "true");
  await expect(page.locator("#bow-direction")).toHaveAttribute("data-direction", "backward");
  await page.mouse.up();
  await expect(studio).toHaveAttribute("data-sounding", "false");
  await expect(page.locator("#selection")).toContainText("전체 1개");
});

test("narrow touch layout keeps the instrument and controls usable", async ({ browser }) => {
  const context = await browser.newContext({ viewport: { width: 360, height: 740 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const page = await context.newPage();
  await page.goto("/");
  await page.getByRole("button", { name: "활로 켜기", exact: true }).tap();
  await page.getByRole("button", { name: "연습 현 놓기" }).tap();
  const bounds = await page.locator("#bow-studio").boundingBox();
  expect(bounds!.x).toBeGreaterThanOrEqual(0);
  expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(360);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(360);
  await page.getByRole("button", { name: "한 활 연주", exact: true }).tap();
  await expect(page.locator("#bow-studio")).toHaveAttribute("data-sounding", "true");
  await page.getByRole("button", { name: "일시정지", exact: true }).tap();
  await expect(page.locator("#bow-studio")).toHaveAttribute("data-sounding", "false");
  await expect(page.getByRole("slider", { name: "활의 압력" })).toBeDisabled();
  await expect(page.getByRole("button", { name: "한 활 연주", exact: true })).toBeDisabled();
  await page.getByRole("button", { name: "재생", exact: true }).tap();
  await page.getByRole("button", { name: "한 활 연주", exact: true }).tap();
  await expect(page.locator("#bow-studio")).toHaveAttribute("data-sounding", "true");
  await context.close();
});

test("a touch stroke keeps its first finger and cancels without a stuck note", async ({ browser }) => {
  const context = await browser.newContext({ viewport: { width: 360, height: 740 }, isMobile: true, hasTouch: true });
  const page = await context.newPage();
  await page.goto("/");
  await page.getByRole("button", { name: "활로 켜기", exact: true }).tap();
  await page.getByRole("button", { name: "연습 현 놓기" }).tap();
  const cdp = await context.newCDPSession(page);
  const finger = (id: number, x: number) => ({ id, x, y: 230, radiusX: 4, radiusY: 4, force: 0.5 });
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [finger(0, 153)] });
  await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [finger(0, 175)] });
  await expect(page.locator("#bow-studio")).toHaveAttribute("data-sounding", "true");
  await expect(page.locator("#bow-note")).toHaveText("D4");
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [finger(0, 175), finger(1, 260)] });
  await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [finger(0, 185), finger(1, 290)] });
  await expect(page.locator("#bow-note")).toHaveText("D4");
  await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [finger(0, 185)] });
  await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [finger(0, 155)] });
  await expect(page.locator("#bow-studio")).toHaveAttribute("data-sounding", "true");
  await expect(page.locator("#bow-note")).toHaveText("D4");
  await cdp.send("Input.dispatchTouchEvent", { type: "touchCancel", touchPoints: [] });
  await expect(page.locator("#bow-studio")).toHaveAttribute("data-sounding", "false");
  await expect(page.locator("#stage")).toHaveCSS("cursor", "grab");
  await expect(page.locator("#selection")).toContainText("전체 4개");
  await context.close();
});
