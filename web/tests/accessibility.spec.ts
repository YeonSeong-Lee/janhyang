import { expect, test, type Locator, type Page } from "@playwright/test";

async function tabTo(page: Page, target: Locator): Promise<void> {
  for (let i = 0; i < 30; i++) {
    await page.keyboard.press("Tab");
    if (await target.evaluate((element) => element === document.activeElement)) return;
  }
  await expect(target).toBeFocused();
}

test("the closed help disclosure paints a visible keyboard focus indicator", async ({ page }) => {
  // Keep the drawing surface static so pixel changes come from focus alone.
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  const summary = page.locator("summary");
  await tabTo(page, summary);
  await expect(summary).toBeFocused();
  const focused = await page.screenshot();
  await summary.evaluate((element) => element.blur());
  const unfocused = await page.screenshot();
  expect(focused.equals(unfocused), "the outline must not be clipped by details").toBe(false);
});

test("forced colors keep the playback icon in every state", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce", forcedColors: "active" });
  let finishLoading!: () => void;
  const gate = new Promise<void>((resolve) => { finishLoading = resolve; });
  await page.route("**/janhyang.riv", async (route) => {
    await gate;
    await route.continue();
  });
  try {
    await page.goto("/");
    const playback = page.locator("#playback");
    const iconIsPainted = async (phase: string) => {
      await expect(playback).toHaveAttribute("data-phase", phase);
      const box = (await playback.boundingBox())!;
      // Only the opaque middle of the button, so the water behind it cannot differ between captures.
      const clip = { x: box.x + box.width / 2 - 9, y: box.y + box.height / 2 - 9, width: 18, height: 18 };
      const painted = await page.screenshot({ clip });
      const style = await page.addStyleTag({ content: "#playback::before { visibility: hidden !important; }" });
      const blank = await page.screenshot({ clip });
      await style.evaluate((element) => (element as Element).remove());
      expect(painted.equals(blank), `${phase} icon`).toBe(false);
    };
    await iconIsPainted("idle");
    await playback.click();
    await iconIsPainted("loading");
    finishLoading();
    await iconIsPainted("playing");
  } finally {
    finishLoading();
  }
});

test("forced colors draw the focus ring on each capsule instead of the dark water", async ({ page, browserName }) => {
  test.skip(browserName === "webkit", "WebKit has no forced colors mode");
  await page.emulateMedia({ reducedMotion: "reduce", forcedColors: "active", colorScheme: "light" });
  await page.goto("/");
  await expect(page.locator(".language-picker")).toBeVisible();
  for (const [target, capsule] of [["#playback", "#playback"], [".controls summary", ".controls summary"], ["#language", ".language-picker"]]) {
    const control = page.locator(target);
    await tabTo(page, control);
    const { x, y, width, height } = (await page.locator(capsule).boundingBox())!;
    // A slice through the middle: a ring around the outside would reach into the rounded corners.
    const clip = { x: x + width / 2 - 3, y, width: 6, height };
    const focused = await page.screenshot({ clip });
    await control.evaluate((element) => (element as HTMLElement).blur());
    expect(focused.equals(await page.screenshot({ clip })), target).toBe(false);
  }
});

test("a slow instrument announces loading and completion through the existing live region", async ({ page }) => {
  let finishLoading!: () => void;
  const gate = new Promise<void>((resolve) => { finishLoading = resolve; });
  await page.route("**/janhyang.riv", async (route) => {
    await gate;
    await route.continue();
  });
  try {
    await page.goto("/");
    const status = page.locator("#status");
    await expect(status).toHaveAttribute("role", "status");
    await expect(status).toHaveAttribute("aria-live", "polite");
    await expect(status).toHaveText("수면을 준비하고 있습니다…");
    await expect(page.getByRole("heading", { name: "당신의 손끝에서, 첫 울림이 시작됩니다." })).toBeVisible();
    await expect(page.locator("#stage")).toHaveJSProperty("inert", true);
    await expect(page.locator("#loading-caption")).toHaveText("준비가 조금 길어지고 있어요");
    await expect(status).toContainText("연결 상태에 따라 시간이 걸릴 수 있습니다");
    finishLoading();
    await expect(page.getByRole("button", { name: "일시정지", exact: true })).toBeEnabled();
    await expect(status).toContainText("수면을 준비했습니다");
    await expect(page.locator("#loading-screen")).toBeHidden();
    await expect(page.locator("#stage")).toHaveJSProperty("inert", false);
  } finally {
    finishLoading();
  }
});

test("keyboard activates instrument controls with native length selection, respecting pause", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  await tabTo(page, page.getByRole("button", { name: "재생", exact: true }));
  await page.keyboard.press("Enter");
  await expect(page.getByRole("button", { name: "일시정지", exact: true })).toBeEnabled();
  await tabTo(page, page.locator("summary"));
  await page.keyboard.press("Enter");
  const length = page.getByLabel("새 현 길이");
  await tabTo(page, length);
  // macOS headless Chromium does not drive the OS select popup with keys,
  // even in a standalone select fixture. Use its native selection API here;
  // focus traversal and every instrument action below remain keyboard-only.
  await length.selectOption("0.3");
  await expect(length).toHaveValue("0.3");
  const create = page.getByRole("button", { name: "현 만들기", exact: true });
  await tabTo(page, create);
  await page.keyboard.press("Enter");
  const selection = page.locator("#selection");
  await expect(selection).toContainText("전체 1개 중 1번째 현");
  await expect(page.locator(".water-intro")).toHaveCSS("opacity", "0");
  const firstDescription = await selection.textContent();
  await page.keyboard.press("Shift+Tab");
  await expect(length).toBeFocused();
  await length.selectOption("0.5");
  await tabTo(page, create);
  await page.keyboard.press("Space");
  await expect(selection).toContainText("전체 2개 중 2번째 현");
  expect((await selection.textContent())?.split("·")[1]).not.toBe(firstDescription?.split("·")[1]);
  const previous = page.getByRole("button", { name: "이전 현", exact: true });
  await tabTo(page, previous);
  await page.keyboard.press("Enter");
  await expect(selection).toContainText("전체 2개 중 1번째 현");
  await tabTo(page, page.getByRole("button", { name: "다음 현", exact: true }));
  await page.keyboard.press("Space");
  await expect(selection).toContainText("전체 2개 중 2번째 현");
  await tabTo(page, page.getByRole("button", { name: "선택한 현 튕기기", exact: true }));
  await page.keyboard.press("Enter");
  await expect(selection).toContainText("선택한 현을 튕겼습니다");

  await tabTo(page, page.getByRole("button", { name: "일시정지", exact: true }));
  await page.keyboard.press("Enter");
  await expect(create).toBeDisabled();
  await tabTo(page, create);
  await page.keyboard.press("Enter");
  await tabTo(page, page.getByRole("button", { name: "재생", exact: true }));
  await page.keyboard.press("Enter");
  await tabTo(page, previous);
  await page.keyboard.press("Enter");
  await expect(selection).toContainText("전체 2개 중 1번째 현");
});

test("button controls include strings drawn with a pointer", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("button", { name: "일시정지", exact: true })).toBeEnabled();
  const intro = page.locator(".water-intro");
  await expect(intro).toHaveCSS("opacity", "1");
  await page.mouse.move(60, 100);
  await page.mouse.down();
  await expect(intro).toHaveCSS("opacity", "0");
  await page.mouse.move(260, 100, { steps: 12 });
  await page.mouse.up();
  const selection = page.locator("#selection");
  await expect(selection).toContainText("전체 1개 중 1번째 현");
  await page.locator("summary").click();
  await page.getByRole("button", { name: "현 만들기", exact: true }).click();
  await expect(selection).toContainText("전체 2개 중 2번째 현");
  await page.getByRole("button", { name: "이전 현", exact: true }).click();
  await expect(selection).toContainText("전체 2개 중 1번째 현");
  await page.getByRole("button", { name: "선택한 현 튕기기", exact: true }).click();
  await expect(selection).toContainText("선택한 현을 튕겼습니다");
});
