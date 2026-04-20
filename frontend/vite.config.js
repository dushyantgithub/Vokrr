import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  build: {
    assetsDir: "app-assets",
  },
  server: {
    host: "0.0.0.0",
    port: 5173,
    proxy: {
      "/api": "http://localhost:8080",
      "/ws": {
        target: "ws://localhost:8080",
        ws: true,
      },
    },
  },
});

