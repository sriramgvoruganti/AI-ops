import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    host: true,
    port: 5173,
    proxy: {
      // In Docker the backend is reachable as "backend"; locally it's localhost.
      "/api": process.env.API_PROXY_TARGET ?? "http://localhost:8000",
    },
  },
});
