import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  fullyParallel: true,
  workers: 2,
  timeout: 45000,
  expect: { timeout: 15000 },
  use: {
    baseURL: "http://127.0.0.1:4187",
    browserName: "chromium",
    trace: "retain-on-failure",
  },
  webServer: [
    {
      command: "pnpm exec vite preview --host 127.0.0.1 --port 4187 --strictPort",
      url: "http://127.0.0.1:4187",
    },
    {
      command: "node tests/static-server.mjs",
      url: "http://127.0.0.1:4188/janhyang/",
    },
  ],
});
