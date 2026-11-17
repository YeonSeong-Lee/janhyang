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
