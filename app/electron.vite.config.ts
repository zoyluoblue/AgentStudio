import { resolve } from "node:path";
import { defineConfig, externalizeDepsPlugin } from "electron-vite";
import react from "@vitejs/plugin-react";

// Alias @engine -> the compiled engine library (repo/dist/core.js).
// npm scripts run from app/, so process.cwd() is app/ and ../dist is repo/dist.
const engine = resolve(process.cwd(), "..", "dist", "core.js");

export default defineConfig({
  main: {
    plugins: [externalizeDepsPlugin()],
    resolve: { alias: { "@engine": engine } },
    build: { rollupOptions: { input: resolve(process.cwd(), "src/main/index.ts") } },
  },
  preload: {
    plugins: [externalizeDepsPlugin()],
    build: { rollupOptions: { input: resolve(process.cwd(), "src/preload/index.ts") } },
  },
  renderer: {
    root: resolve(process.cwd(), "src/renderer"),
    plugins: [react()],
    build: { rollupOptions: { input: resolve(process.cwd(), "src/renderer/index.html") } },
  },
});
