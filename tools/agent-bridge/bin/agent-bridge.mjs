#!/usr/bin/env node

import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import {
  bridgeDatabasePath,
  bridgeState,
  closeStore,
  commandAvailability,
  initializeProject,
  openStore,
  postMessage,
  resolveProjectRoot
} from "../src/core.mjs";

const binDirectory = path.dirname(fileURLToPath(import.meta.url));
const packageRoot = path.resolve(binDirectory, "..");
const serverPath = path.join(packageRoot, "src", "server.mjs");
const CLAUDE_TOOL_PERMISSIONS = [
  "mcp__agent-bridge__bridge_status",
  "mcp__agent-bridge__git_overview",
  "mcp__agent-bridge__get_messages",
  "mcp__agent-bridge__post_message",
  "mcp__agent-bridge__create_task",
  "mcp__agent-bridge__claim_task",
  "mcp__agent-bridge__submit_for_review",
  "mcp__agent-bridge__review_task",
  "mcp__agent-bridge__integrate_task",
  "mcp__agent-bridge__initialize_project"
];

function option(args, name, fallback) {
  const index = args.indexOf(name);
  if (index === -1) return fallback;
  const value = args[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`${name} benötigt einen Wert.`);
  args.splice(index, 2);
  return value;
}

function flag(args, name) {
  const index = args.indexOf(name);
  if (index === -1) return false;
  args.splice(index, 1);
  return true;
}

function execute(command, args, cwd = process.cwd()) {
  return spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    env: process.env
  });
}

function configurationState(command) {
  const result = execute(command, ["mcp", "get", "agent-bridge"]);
  return {
    configured: result.status === 0,
    detail: (result.stdout || result.stderr || "").trim()
  };
}

function configureClaudePermissions() {
  const configDirectory = process.env.CLAUDE_CONFIG_DIR
    ? path.resolve(process.env.CLAUDE_CONFIG_DIR)
    : path.join(homedir(), ".claude");
  const settingsPath = path.join(configDirectory, "settings.json");
  mkdirSync(configDirectory, { recursive: true });
  let settings = {};
  if (existsSync(settingsPath)) {
    try {
      settings = JSON.parse(readFileSync(settingsPath, "utf8"));
    } catch {
      throw new Error(`${settingsPath} enthält ungültiges JSON und wurde nicht verändert.`);
    }
  }
  const current = Array.isArray(settings.permissions?.allow) ? settings.permissions.allow : [];
  const allow = [...new Set([...current, ...CLAUDE_TOOL_PERMISSIONS])];
  const added = allow.length - current.length;
  if (added > 0) {
    const temporaryPath = `${settingsPath}.agent-bridge-${process.pid}`;
    const next = {
      ...settings,
      permissions: {
        ...(settings.permissions ?? {}),
        allow
      }
    };
    writeFileSync(temporaryPath, `${JSON.stringify(next, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
    renameSync(temporaryPath, settingsPath);
  }
  return { settingsPath, added };
}

function configureClients(options = {}) {
  const availability = commandAvailability();
  const nodeCommand = availability.node.path || process.execPath;
  const results = [];
  if (availability.claude.available) {
    const current = configurationState("claude");
    let permissions;
    try {
      permissions = configureClaudePermissions();
    } catch (error) {
      permissions = { error: error instanceof Error ? error.message : String(error) };
    }
    if (current.configured && !options.force) {
      results.push({ client: "Claude Code", status: "preserved", detail: "Vorhandene Konfiguration wurde nicht überschrieben.", permissions });
    } else {
      if (current.configured) execute("claude", ["mcp", "remove", "agent-bridge", "--scope", "user"]);
      const added = execute("claude", [
        "mcp", "add",
        "--transport", "stdio",
        "--scope", "user",
        "agent-bridge",
        "--", nodeCommand, serverPath
      ]);
      results.push({
        client: "Claude Code",
        status: added.status === 0 ? "configured" : "failed",
        detail: (added.stdout || added.stderr || "").trim(),
        permissions
      });
    }
  } else {
    results.push({ client: "Claude Code", status: "missing", detail: "Befehl claude wurde nicht gefunden." });
  }

  if (availability.codex.available) {
    const current = configurationState("codex");
    if (current.configured && !options.force) {
      results.push({ client: "Codex", status: "preserved", detail: "Vorhandene Konfiguration wurde nicht überschrieben." });
    } else {
      if (current.configured) execute("codex", ["mcp", "remove", "agent-bridge"]);
      const added = execute("codex", ["mcp", "add", "agent-bridge", "--", nodeCommand, serverPath]);
      results.push({
        client: "Codex",
        status: added.status === 0 ? "configured" : "failed",
        detail: (added.stdout || added.stderr || "").trim()
      });
    }
  } else {
    results.push({ client: "Codex", status: "missing", detail: "Befehl codex wurde nicht gefunden." });
  }
  return results;
}

function printHelp() {
  process.stdout.write(`Agent Bridge by CreativTechnik\n\n`);
  process.stdout.write(`Befehle:\n`);
  process.stdout.write(`  agent-bridge dashboard [--root PFAD] [--port 47831] [--no-open]\n`);
  process.stdout.write(`  agent-bridge init [--root PFAD]\n`);
  process.stdout.write(`  agent-bridge status [--root PFAD]\n`);
  process.stdout.write(`  agent-bridge message TEXT [--root PFAD]\n`);
  process.stdout.write(`  agent-bridge configure [--force]\n`);
  process.stdout.write(`  agent-bridge doctor [--root PFAD]\n`);
  process.stdout.write(`  agent-bridge mcp\n`);
}

async function main() {
  const args = process.argv.slice(2);
  const command = args.shift() ?? "help";

  if (["help", "--help", "-h"].includes(command)) {
    printHelp();
    return;
  }

  if (command === "mcp") {
    await import("../src/server.mjs");
    return;
  }

  const explicitRoot = option(args, "--root", null);
  const root = resolveProjectRoot(explicitRoot);

  if (command === "dashboard") {
    const port = Number(option(args, "--port", "47831"));
    const noOpen = flag(args, "--no-open");
    if (args.length) throw new Error(`Unbekannte Argumente: ${args.join(" ")}`);
    const { startDashboard } = await import("../src/dashboard.mjs");
    const dashboard = await startDashboard({ root, port, open: !noOpen });
    process.stdout.write(`Agent Bridge läuft für ${dashboard.root}\n${dashboard.url}\n`);
    const stop = async () => {
      await dashboard.close();
      process.exit(0);
    };
    process.on("SIGINT", stop);
    process.on("SIGTERM", stop);
    return;
  }

  const database = openStore();
  try {
    if (command === "init") {
      if (args.length) throw new Error(`Unbekannte Argumente: ${args.join(" ")}`);
      process.stdout.write(`${JSON.stringify(initializeProject(database, root), null, 2)}\n`);
      return;
    }
    if (command === "status") {
      if (args.length) throw new Error(`Unbekannte Argumente: ${args.join(" ")}`);
      process.stdout.write(`${JSON.stringify(bridgeState(database, root, { includeDone: true }), null, 2)}\n`);
      return;
    }
    if (command === "message") {
      const body = args.join(" ").trim();
      process.stdout.write(`${JSON.stringify(postMessage(database, root, {
        sender: "user",
        recipients: ["codex", "claude"],
        body
      }), null, 2)}\n`);
      return;
    }
    if (command === "configure") {
      const force = flag(args, "--force");
      if (args.length) throw new Error(`Unbekannte Argumente: ${args.join(" ")}`);
      process.stdout.write(`${JSON.stringify(configureClients({ force }), null, 2)}\n`);
      return;
    }
    if (command === "doctor") {
      const clients = commandAvailability();
      const configuration = {
        claude: clients.claude.available ? configurationState("claude") : { configured: false, detail: "nicht installiert" },
        codex: clients.codex.available ? configurationState("codex") : { configured: false, detail: "nicht installiert" }
      };
      process.stdout.write(`${JSON.stringify({
        ok: clients.node.available && clients.claude.available && clients.codex.available,
        root,
        database: bridgeDatabasePath(),
        clients,
        configuration,
        state: bridgeState(database, root)
      }, null, 2)}\n`);
      return;
    }
    throw new Error(`Unbekannter Befehl: ${command}`);
  } finally {
    closeStore(database);
  }
}

main().catch(error => {
  process.stderr.write(`Agent Bridge: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
});
