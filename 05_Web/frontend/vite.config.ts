import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "node:path";

// Dev proxy to FastAPI. Use 127.0.0.1 (not localhost) to avoid IPv6 ::1
// vs IPv4 127.0.0.1 socket mismatch.
export default defineConfig({
  base: "./",
  plugins: [react()],
  resolve: { alias: { "@": path.resolve(__dirname, "src") } },
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      "/api": { target: "http://127.0.0.1:8000", changeOrigin: true },
      "/assets": { target: "http://127.0.0.1:8000", changeOrigin: true },
    },
  },
});
