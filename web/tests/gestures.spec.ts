import { expect, test, type Page } from "@playwright/test";

async function ready(page: Page): Promise<void> {
  await page.goto("/?debug");
  await expect(page.getByRole("button", { name: "일시정지", exact: true })).toBeEnabled();
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
  await expect(page.locator("#drag-guide")).toHaveCSS("opacity", "0");
  await page.mouse.down();
  await expect(canvas).toHaveCSS("cursor", "grabbing");
  await page.mouse.move(300, 260, { steps: 8 });
  await expect(page.locator("#drag-guide")).toHaveAttribute("data-visible", "true");
  await expect(page.locator("#gesture-hint")).toContainText("당겼다가 놓아보세요");
  await page.mouse.up();
  await page.mouse.move(50, 500);
  await expect(canvas).toHaveCSS("cursor", "crosshair");
  await expect(page.locator("#drag-guide")).toHaveCSS("opacity", "0");
  await page.locator("summary").click();
  await expect(page.locator("#selection")).toContainText("전체 1개");
});

test("blur, pause and button actions cancel a held string", async ({ page }) => {
  await ready(page);
  await draw(page, 200);
  const canvas = page.locator("#stage");
  await page.mouse.move(300, 200);
  await page.mouse.down();
  await expect(canvas).toHaveCSS("cursor", "grabbing");
  await page.evaluate(() => window.dispatchEvent(new Event("blur")));
  await expect(canvas).toHaveCSS("cursor", "crosshair");
  await page.mouse.up();

  await page.mouse.move(300, 200);
  await page.mouse.down();
  await expect(canvas).toHaveCSS("cursor", "grabbing");
  // Keyboard activation must stop a gesture even with the mouse held down.
  await page.getByRole("button", { name: "일시정지", exact: true }).focus();
  await page.keyboard.press("Enter");
  await expect(canvas).toHaveJSProperty("inert", true);
  await expect(canvas).toHaveCSS("cursor", "default");
  await page.mouse.up();
  await page.keyboard.press("Enter");
  await page.mouse.move(50, 500);
  await expect(canvas).toHaveCSS("cursor", "crosshair");

  await page.locator("summary").click();
  await page.mouse.move(300, 200);
  await page.mouse.down();
  await expect(canvas).toHaveCSS("cursor", "grabbing");
  await page.getByRole("button", { name: "현 만들기", exact: true }).focus();
  await page.keyboard.press("Enter");
  await expect(canvas).toHaveCSS("cursor", "crosshair");
  await page.mouse.up();
  await expect(page.locator("#selection")).toContainText("전체 2개");
});
