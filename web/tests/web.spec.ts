import { expect, test } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

const fallbackURL = "http://127.0.0.1:4188/janhyang/?debug";

test("loads the real instrument and all binaries from the same origin", async ({ page }) => {
  const requests: string[] = [];
  const errors: string[] = [];
  page.on("request", (request) => requests.push(request.url()));
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto("/?debug");
  await expect(page.getByRole("button", { name: "일시정지" })).toBeEnabled();
  await expect(page.getByRole("region", { name: "진단 정보" })).toContainText("isolated: true");
  expect(requests.some((url) => url.endsWith(".wasm"))).toBe(true);
  expect(requests.filter((url) => new URL(url).origin !== "http://127.0.0.1:4187")).toEqual([]);
  expect(errors).toEqual([]);
  await page.getByText("사용 안내", { exact: true }).click();
  const accessibility = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21aa", "wcag22aa"]).analyze();
  expect(accessibility.violations).toEqual([]);
});

test("reduced motion defers the instrument until keyboard activation", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  const resources: string[] = [];
  page.on("request", (request) => {
    if (/\.(riv|wasm)$|\/player-/.test(request.url())) resources.push(request.url());
  });
  await page.goto("/");
  const play = page.getByRole("button", { name: "재생", exact: true });
  await expect(play).toBeEnabled();
  await expect(page.getByRole("status")).toContainText("움직임 줄이기");
  expect(resources).toEqual([]);
  await page.keyboard.press("Tab");
  await expect(play).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page.getByRole("button", { name: "일시정지" })).toBeEnabled();
  await page.keyboard.press("Space");
  await expect(play).toBeFocused();
  await expect(play).toBeEnabled();
});

test("pause survives viewport and motion preference changes", async ({ page }) => {
  await page.addInitScript(() => {
    const state = { frames: 0 };
    Object.assign(window, { renderProbe: state });
    const requestFrame = window.requestAnimationFrame.bind(window);
    window.requestAnimationFrame = (callback) => requestFrame((time) => {
      state.frames++;
      callback(time);
    });
  });
  await page.goto("/?debug");
  const frames = () => page.evaluate(() => (window as unknown as { renderProbe: { frames: number } }).renderProbe.frames);
  await expect.poll(frames).toBeGreaterThan(5);
  await page.getByRole("button", { name: "일시정지" }).click();
  await page.setViewportSize({ width: 390, height: 650 });
  await expect(page.locator("#stage")).toHaveJSProperty("width", 390);
  await expect(page.locator("#stage")).toHaveJSProperty("inert", true);
  // The runtime completes one paused frame to reset its playback clock.
  await page.evaluate(() => new Promise<void>((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
  }));
  // Observe a quiet interval: an accidental render loop would keep advancing.
  const counts = await page.evaluate(async () => {
    const state = (window as unknown as { renderProbe: { frames: number } }).renderProbe;
    const before = state.frames;
    await new Promise((resolve) => setTimeout(resolve, 200));
    return [before, state.frames];
  });
  expect(counts[1]).toBe(counts[0]);
  await expect(page.getByRole("button", { name: "재생", exact: true })).toBeEnabled();
  await page.getByRole("button", { name: "재생", exact: true }).click();
  await expect.poll(frames).toBeGreaterThan(counts[1]);
  await page.emulateMedia({ reducedMotion: "reduce" });
  await expect(page.getByRole("button", { name: "재생", exact: true })).toBeEnabled();
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await expect(page.getByRole("button", { name: "재생", exact: true })).toBeEnabled();
});

test("resizes the drawing surface on a high-density narrow viewport", async ({ browser }) => {
  const context = await browser.newContext({
    viewport: { width: 320, height: 568 },
    deviceScaleFactor: 2,
  });
  const page = await context.newPage();
  await page.goto("http://127.0.0.1:4187/");
  await expect(page.getByRole("button", { name: "일시정지" })).toBeEnabled();
  await expect(page.locator("#stage")).toHaveJSProperty("width", 640);
  await expect(page.locator("#stage")).toHaveJSProperty("height", 1136);
  await page.getByText("사용 안내", { exact: true }).click();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  const accessibility = await new AxeBuilder({ page }).analyze();
  expect(accessibility.violations).toEqual([]);
  await page.setViewportSize({ width: 390, height: 650 });
  await expect(page.locator("#stage")).toHaveJSProperty("width", 780);
  await expect(page.locator("#stage")).toHaveJSProperty("height", 1300);
  await context.close();
});

test("a failed Rive file exposes an accessible retry action", async ({ page }) => {
  await page.route("**/janhyang.riv", (route) => route.abort());
  await page.goto("/");
  await expect(page.getByRole("status")).toContainText("불러오지 못했습니다");
  const retry = page.getByRole("button", { name: "다시 불러오기" });
  await expect(retry).toBeVisible();
  await page.unroute("**/janhyang.riv");
  await retry.click();
  await expect(page.getByRole("button", { name: "일시정지" })).toBeEnabled();
});

test("failed WASM downloads reach the error state", async ({ page }) => {
  await page.route("**/*.wasm", (route) => route.abort());
  await page.goto("/");
  await expect(page.getByRole("status")).toContainText("불러오지 못했습니다");
  await expect(page.getByRole("button", { name: "다시 불러오기" })).toBeVisible();
});

test("a headerless project path reloads once and gains isolation", async ({ page }) => {
  let navigations = 0;
  let prematureWasm = false;
  page.on("request", (request) => {
    if (request.isNavigationRequest()) navigations++;
    if (request.url().endsWith(".wasm") && navigations < 2) prematureWasm = true;
  });
  await page.goto(fallbackURL);
  await expect(page.getByRole("button", { name: "일시정지" })).toBeEnabled();
  expect(await page.evaluate(() => crossOriginIsolated)).toBe(true);
  expect(navigations).toBe(2);
  expect(prematureWasm).toBe(false);
  expect(await page.evaluate(() => navigator.serviceWorker.controller?.scriptURL)).toBe("http://127.0.0.1:4188/janhyang/coi.js");
});

for (const method of ["getItem", "setItem"] as const) {
  test(`blocked sessionStorage.${method} does not break startup or reload`, async ({ page }) => {
    await page.addInitScript((method) => {
      Storage.prototype[method] = () => { throw new DOMException("Blocked", "SecurityError"); };
    }, method);
    let navigations = 0;
    const errors: string[] = [];
    page.on("request", (request) => { if (request.isNavigationRequest()) navigations++; });
    page.on("pageerror", (error) => errors.push(error.message));
    await page.goto(fallbackURL);
    await expect(page.getByRole("button", { name: "일시정지" })).toBeEnabled();
    expect(navigations).toBe(1);
    expect(errors).toEqual([]);
  });
}

test("worker registration rejection falls back without an unhandled error", async ({ page }) => {
  await page.addInitScript(() => {
    navigator.serviceWorker.register = () => Promise.reject(new Error("Registration blocked"));
  });
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(fallbackURL);
  await expect(page.getByRole("button", { name: "일시정지" })).toBeEnabled();
  await expect(page.getByRole("region", { name: "진단 정보" })).toContainText("Registration blocked");
  expect(errors).toEqual([]);
});

test("an unresponsive worker cannot stall startup indefinitely", async ({ page }) => {
  await page.addInitScript(() => {
    navigator.serviceWorker.register = () => new Promise(() => {});
  });
  await page.goto(fallbackURL);
  await expect(page.getByRole("button", { name: "일시정지" })).toBeEnabled();
  await expect(page.getByRole("region", { name: "진단 정보" })).toContainText("worker timed out");
});

test("JavaScript-disabled visitors get an explanation", async ({ browser }) => {
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto("http://127.0.0.1:4187");
  await expect(page.locator("noscript p")).toBeVisible();
  await expect(page.locator("noscript p")).toContainText("JavaScript를 켜고");
  await expect(page.getByRole("button", { name: "재생", exact: true })).toBeHidden();
  await context.close();
});
