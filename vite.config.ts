import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Two pages: the main window and the floating recording pill.
export default defineConfig({
  plugins: [react()],
  clearScreen: false,
  server: { port: 1420, strictPort: true },
  build: { rollupOptions: { input: { main: "index.html", pill: "pill.html" } } },
});
