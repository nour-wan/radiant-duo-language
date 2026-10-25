// @lovable.dev/vite-tanstack-config already includes the following — do NOT add them manually
// or the app will break with duplicate plugins:
//   - TanStack devtools (dev-only, first), tanstackStart, viteReact, tailwindcss, tsConfigPaths,
//     nitro (build-only), VITE_* env injection, @ path alias,
//     React/TanStack dedupe, error logger plugins, and sandbox detection (port/host/strictPort).
// You can pass additional config via defineConfig({ vite: { ... }, etc... }) if needed.
import { defineConfig } from "@lovable.dev/vite-tanstack-config";

// Explicit self-hosting target; do not depend on CI/provider auto-detection.
// Lovable's managed builds pin their own output; Ubuntu builds use these paths.
export const nodeDeployment = {
  preset: "node-server",
  output: {
    dir: ".output",
    serverDir: ".output/server",
    publicDir: ".output/public",
  },
};

export default defineConfig({
  nitro: nodeDeployment,
  tanstackStart: {
    // Redirect TanStack Start's bundled server entry to src/server.ts (our SSR error wrapper).
    // nitro/vite builds from this
    server: { entry: "server" },
  },
});
