import react from "@vitejs/plugin-react";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

const firstRunHtml = fileURLToPath(new URL("./first-run.html", import.meta.url));
const indexHtml = fileURLToPath(new URL("./index.html", import.meta.url));
const mainHtml = fileURLToPath(new URL("./main.html", import.meta.url));

export default defineConfig({
  plugins: [react()],
  build: {
    outDir: "dist/renderer",
    emptyOutDir: false,
    rollupOptions: {
      input: {
        firstRun: firstRunHtml,
        index: indexHtml,
        main: mainHtml,
      },
    },
  },
  server: {
    port: 5173,
    strictPort: true
  }
});
