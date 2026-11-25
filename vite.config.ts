import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Three pages: the main window, the floating recording pill and the EsyMeet prompt.
export default defineConfig({
  plugins: [react()],
  clearScreen: false,
  server: { port: 1420, strictPort: true },
  build: { rollupOptions: { input: { main: "index.html", pill: "pill.html", prompt: "prompt.html" } } },
});
