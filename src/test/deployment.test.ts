// @vitest-environment node
import { describe, expect, it } from "vitest";
import { nodeDeployment } from "../../vite.config";

describe("Existing Ubuntu VPS deployment", () => {
  it("uses Node rather than a Worker or provider auto-detection", () => {
    expect(nodeDeployment.preset).toBe("node-server");
  });

  it("produces the server directory used by radiant-duo.service", () => {
    expect(nodeDeployment.output.dir).toBe(".output");
    expect(nodeDeployment.output.serverDir).toBe(".output/server");
  });

  it("keeps public assets alongside the deployed server", () => {
    expect(nodeDeployment.output.publicDir).toBe(".output/public");
  });
});