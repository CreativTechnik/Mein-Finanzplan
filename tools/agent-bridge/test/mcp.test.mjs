import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/client";
import { StdioClientTransport } from "@modelcontextprotocol/client/stdio";

const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function parseToolResult(result) {
  const block = result.content.find(item => item.type === "text");
  assert.ok(block, "tool response should contain text");
  return JSON.parse(block.text);
}

test("stdio server exposes resources and coordinates messages", { timeout: 30_000 }, async () => {
  const directory = mkdtempSync(path.join(tmpdir(), "agent-bridge-mcp-"));
  const project = path.join(directory, "project");
  mkdirSync(project);
  execFileSync("git", ["init", "-q"], { cwd: project });

  const environment = Object.fromEntries(
    Object.entries({
      ...process.env,
      AGENT_BRIDGE_PROJECT_ROOT: project,
      AGENT_BRIDGE_DB: path.join(directory, "bridge.sqlite")
    }).filter(([, value]) => typeof value === "string")
  );
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [path.join(packageRoot, "src", "server.mjs")],
    cwd: project,
    env: environment,
    stderr: "pipe"
  });
  const client = new Client({ name: "agent-bridge-test", version: "1.0.0" });

  try {
    await client.connect(transport);

    const tools = await client.listTools();
    const toolNames = tools.tools.map(tool => tool.name);
    assert.ok(toolNames.includes("bridge_status"));
    assert.ok(toolNames.includes("post_message"));
    assert.ok(toolNames.includes("claim_task"));

    const resources = await client.listResources();
    assert.deepEqual(
      resources.resources.map(resource => resource.uri).sort(),
      [
        "agent-bridge://project/handoff",
        "agent-bridge://project/rules",
        "agent-bridge://project/state"
      ]
    );

    const initialized = parseToolResult(await client.callTool({
      name: "initialize_project",
      arguments: {}
    }));
    assert.equal(initialized.root, realpathSync(project));
    assert.equal(initialized.created.length, 4);

    const posted = parseToolResult(await client.callTool({
      name: "post_message",
      arguments: {
        sender: "user",
        recipients: ["codex", "claude"],
        body: "MCP integration test"
      }
    }));
    assert.equal(posted.body, "MCP integration test");

    const messages = parseToolResult(await client.callTool({
      name: "get_messages",
      arguments: { agent: "all" }
    }));
    assert.equal(messages.at(-1).body, "MCP integration test");

    const stateResource = await client.readResource({ uri: "agent-bridge://project/state" });
    const stateBlock = stateResource.contents.find(item => item.uri === "agent-bridge://project/state");
    assert.ok(stateBlock && "text" in stateBlock);
    assert.equal(JSON.parse(stateBlock.text).project.path, realpathSync(project));
  } finally {
    await client.close().catch(() => {});
    rmSync(directory, { recursive: true, force: true });
  }
});
