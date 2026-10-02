import { randomUUID } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { homedir, platform } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { DatabaseSync } from "node:sqlite";

export const AGENTS = ["codex", "claude"];
export const MESSAGE_SENDERS = ["user", "codex", "claude", "system"];
export const TASK_STATUSES = [
  "open",
  "active",
  "review",
  "changes_requested",
  "ready",
  "done"
];

const ACTIVE_TASK_STATUSES = new Set(["active", "review", "changes_requested", "ready"]);
const MAX_MESSAGE_LENGTH = 20_000;
const MAX_TASK_LENGTH = 8_000;

function cleanText(value, maximum, label) {
  const text = String(value ?? "").trim();
  if (!text) throw new Error(`${label} darf nicht leer sein.`);
  if (text.length > maximum) throw new Error(`${label} ist zu lang (maximal ${maximum} Zeichen).`);
  return text;
}

function run(command, args, cwd, timeout = 10_000) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    timeout,
    env: process.env,
    maxBuffer: 2 * 1024 * 1024
  });
  return {
    ok: result.status === 0,
    status: result.status,
    stdout: (result.stdout ?? "").trim(),
    stderr: (result.stderr ?? "").trim(),
    error: result.error?.message ?? null
  };
}

export function resolveProjectRoot(explicitRoot) {
  const candidates = [
    explicitRoot,
    process.env.AGENT_BRIDGE_PROJECT_ROOT,
    process.env.CLAUDE_PROJECT_DIR,
    process.cwd()
  ].filter(Boolean);

  for (const candidate of candidates) {
    const resolved = path.resolve(candidate);
    if (!existsSync(resolved)) continue;
    const git = run("git", ["rev-parse", "--show-toplevel"], resolved);
    if (git.ok && git.stdout) return path.resolve(git.stdout);
    return resolved;
  }

  return process.cwd();
}

export function bridgeDataDirectory() {
  if (process.env.AGENT_BRIDGE_DATA_DIR) return path.resolve(process.env.AGENT_BRIDGE_DATA_DIR);
  if (platform() === "darwin") {
    return path.join(homedir(), "Library", "Application Support", "CreativTechnik", "AgentBridge");
  }
  return path.join(homedir(), ".local", "share", "creativtechnik-agent-bridge");
}

export function bridgeDatabasePath() {
  return process.env.AGENT_BRIDGE_DB
    ? path.resolve(process.env.AGENT_BRIDGE_DB)
    : path.join(bridgeDataDirectory(), "agent-bridge.sqlite");
}

export function openStore(databasePath = bridgeDatabasePath()) {
  const directory = path.dirname(databasePath);
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const defaultDirectory = path.resolve(bridgeDataDirectory());
  if (path.resolve(directory) === defaultDirectory) chmodSync(directory, 0o700);
  const database = new DatabaseSync(databasePath);
  chmodSync(databasePath, 0o600);
  database.exec("PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000; PRAGMA foreign_keys = ON;");
  database.exec(`
    CREATE TABLE IF NOT EXISTS projects (
      path TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      last_seen_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      project_path TEXT NOT NULL,
      sender TEXT NOT NULL,
      recipients_json TEXT NOT NULL,
      kind TEXT NOT NULL DEFAULT 'chat',
      body TEXT NOT NULL,
      round_id TEXT,
      created_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS messages_project_id
      ON messages(project_path, id);

    CREATE TABLE IF NOT EXISTS tasks (
      id TEXT PRIMARY KEY,
      project_path TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT NOT NULL,
      files_json TEXT NOT NULL,
      status TEXT NOT NULL,
      owner TEXT,
      reviewer TEXT,
      integrator TEXT,
      summary TEXT,
      created_by TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS tasks_project_status
      ON tasks(project_path, status, updated_at);

    CREATE TABLE IF NOT EXISTS reviews (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      task_id TEXT NOT NULL,
      reviewer TEXT NOT NULL,
      verdict TEXT NOT NULL,
      note TEXT NOT NULL,
      created_at TEXT NOT NULL,
      FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE
    );
  `);
  return database;
}

function now() {
  return new Date().toISOString();
}

function projectName(root) {
  return path.basename(root) || root;
}

export function canonicalProjectPath(root) {
  const resolvedWorkspace = path.resolve(root);
  const workspacePath = existsSync(resolvedWorkspace) ? realpathSync.native(resolvedWorkspace) : resolvedWorkspace;
  const commonDirectory = run("git", ["rev-parse", "--git-common-dir"], workspacePath);
  if (!commonDirectory.ok || !commonDirectory.stdout) return workspacePath;
  const resolvedCommonPath = path.resolve(workspacePath, commonDirectory.stdout);
  const commonPath = existsSync(resolvedCommonPath) ? realpathSync.native(resolvedCommonPath) : resolvedCommonPath;
  const bare = run("git", ["rev-parse", "--is-bare-repository"], workspacePath);
  if (bare.ok && bare.stdout === "true") return commonPath;
  return path.basename(commonPath) === ".git" ? path.dirname(commonPath) : commonPath;
}

export function registerProject(database, root) {
  const workspacePath = path.resolve(root);
  const projectPath = canonicalProjectPath(workspacePath);
  const timestamp = now();
  database.prepare(`
    INSERT INTO projects(path, name, created_at, last_seen_at)
    VALUES (?, ?, ?, ?)
    ON CONFLICT(path) DO UPDATE SET name = excluded.name, last_seen_at = excluded.last_seen_at
  `).run(projectPath, projectName(projectPath), timestamp, timestamp);
  return {
    path: workspacePath,
    coordinationPath: projectPath,
    name: projectName(projectPath),
    lastSeenAt: timestamp
  };
}

function normalizeRecipients(recipients) {
  const values = Array.isArray(recipients) ? recipients : [recipients ?? "all"];
  const normalized = [...new Set(values.map(value => String(value).toLowerCase()))];
  if (normalized.includes("all")) return ["codex", "claude"];
  for (const recipient of normalized) {
    if (!AGENTS.includes(recipient) && recipient !== "user") {
      throw new Error(`Unbekannter Empfänger: ${recipient}`);
    }
  }
  return normalized;
}

export function postMessage(database, root, input) {
  const project = registerProject(database, root);
  const sender = String(input.sender ?? "user").toLowerCase();
  if (!MESSAGE_SENDERS.includes(sender)) throw new Error(`Unbekannter Absender: ${sender}`);
  const recipients = normalizeRecipients(input.recipients ?? ["codex", "claude"]);
  const body = cleanText(input.body, MAX_MESSAGE_LENGTH, "Nachricht");
  const kind = cleanText(input.kind ?? "chat", 64, "Nachrichtenart");
  const roundId = input.roundId ? cleanText(input.roundId, 128, "Runden-ID") : null;
  const createdAt = now();
  const result = database.prepare(`
    INSERT INTO messages(project_path, sender, recipients_json, kind, body, round_id, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `).run(project.coordinationPath, sender, JSON.stringify(recipients), kind, body, roundId, createdAt);
  return {
    id: Number(result.lastInsertRowid),
    projectPath: project.coordinationPath,
    sender,
    recipients,
    kind,
    body,
    roundId,
    createdAt
  };
}

export function listMessages(database, root, options = {}) {
  const project = registerProject(database, root);
  const limit = Math.max(1, Math.min(Number(options.limit ?? 100), 500));
  const afterId = Math.max(0, Number(options.afterId ?? 0));
  const agent = String(options.agent ?? "all").toLowerCase();
  const rows = database.prepare(`
    SELECT id, sender, recipients_json, kind, body, round_id, created_at
    FROM messages
    WHERE project_path = ? AND id > ?
    ORDER BY id DESC
    LIMIT ?
  `).all(project.coordinationPath, afterId, limit);

  return rows.reverse().map(row => ({
    id: Number(row.id),
    sender: row.sender,
    recipients: JSON.parse(row.recipients_json),
    kind: row.kind,
    body: row.body,
    roundId: row.round_id,
    createdAt: row.created_at
  })).filter(message => (
    agent === "all"
    || message.sender === agent
    || message.recipients.includes(agent)
  ));
}

export function normalizeFiles(files) {
  const values = Array.isArray(files) ? files : [];
  return [...new Set(values.map(value => {
    const normalized = path.posix.normalize(String(value).replaceAll("\\", "/").trim());
    if (!normalized || normalized === "." || normalized.startsWith("../") || path.posix.isAbsolute(normalized)) {
      throw new Error(`Ungültiger relativer Dateipfad: ${value}`);
    }
    return normalized;
  }))].sort();
}

function pathsOverlap(left, right) {
  return left === right || left.startsWith(`${right}/`) || right.startsWith(`${left}/`);
}

function taskFromRow(row) {
  if (!row) return null;
  return {
    id: row.id,
    title: row.title,
    description: row.description,
    files: JSON.parse(row.files_json),
    status: row.status,
    owner: row.owner,
    reviewer: row.reviewer,
    integrator: row.integrator,
    summary: row.summary,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

export function listTasks(database, root, options = {}) {
  const project = registerProject(database, root);
  const includeDone = Boolean(options.includeDone);
  const rows = includeDone
    ? database.prepare("SELECT * FROM tasks WHERE project_path = ? ORDER BY updated_at DESC").all(project.coordinationPath)
    : database.prepare("SELECT * FROM tasks WHERE project_path = ? AND status != 'done' ORDER BY updated_at DESC").all(project.coordinationPath);
  return rows.map(taskFromRow);
}

export function createTask(database, root, input) {
  const project = registerProject(database, root);
  const title = cleanText(input.title, 300, "Aufgabentitel");
  const description = cleanText(input.description ?? title, MAX_TASK_LENGTH, "Aufgabenbeschreibung");
  const createdBy = cleanText(input.createdBy ?? "user", 64, "Ersteller").toLowerCase();
  if (!MESSAGE_SENDERS.includes(createdBy)) throw new Error(`Unbekannter Ersteller: ${createdBy}`);
  const files = normalizeFiles(input.files ?? []);
  const id = randomUUID();
  const timestamp = now();
  database.prepare(`
    INSERT INTO tasks(
      id, project_path, title, description, files_json, status, owner, reviewer,
      integrator, summary, created_by, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, 'open', NULL, NULL, NULL, NULL, ?, ?, ?)
  `).run(id, project.coordinationPath, title, description, JSON.stringify(files), createdBy, timestamp, timestamp);
  postMessage(database, root, {
    sender: "system",
    recipients: ["codex", "claude"],
    kind: "task",
    body: `Neue Aufgabe: ${title}`,
    roundId: id
  });
  return taskFromRow(database.prepare("SELECT * FROM tasks WHERE id = ?").get(id));
}

function requireAgent(agent) {
  const normalized = String(agent ?? "").toLowerCase();
  if (!AGENTS.includes(normalized)) throw new Error(`Unbekannter Agent: ${agent}`);
  return normalized;
}

export function claimTask(database, root, input) {
  const agent = requireAgent(input.agent);
  const taskId = cleanText(input.taskId, 128, "Aufgaben-ID");
  const projectPath = canonicalProjectPath(root);
  database.exec("BEGIN IMMEDIATE");
  try {
    const row = database.prepare("SELECT * FROM tasks WHERE id = ? AND project_path = ?").get(taskId, projectPath);
    if (!row) throw new Error("Aufgabe wurde in diesem Projekt nicht gefunden.");
    if (row.status === "done") throw new Error("Abgeschlossene Aufgaben können nicht erneut beansprucht werden.");
    if (row.owner && row.owner !== agent) throw new Error(`Aufgabe ist bereits von ${row.owner} beansprucht.`);
    const files = normalizeFiles(input.files?.length ? input.files : JSON.parse(row.files_json));
    const activeRows = database.prepare("SELECT * FROM tasks WHERE project_path = ? AND id != ?").all(projectPath, taskId);
    for (const activeRow of activeRows) {
      if (!ACTIVE_TASK_STATUSES.has(activeRow.status)) continue;
      const activeFiles = JSON.parse(activeRow.files_json);
      const collision = files.find(file => activeFiles.some(activeFile => pathsOverlap(file, activeFile)));
      if (collision) {
        throw new Error(`Dateikonflikt mit Aufgabe '${activeRow.title}' bei ${collision}.`);
      }
    }
    const timestamp = now();
    database.prepare(`
      UPDATE tasks SET files_json = ?, status = 'active', owner = ?, updated_at = ?
      WHERE id = ?
    `).run(JSON.stringify(files), agent, timestamp, taskId);
    database.exec("COMMIT");
    return taskFromRow(database.prepare("SELECT * FROM tasks WHERE id = ?").get(taskId));
  } catch (error) {
    database.exec("ROLLBACK");
    throw error;
  }
}

export function submitTaskForReview(database, root, input) {
  const agent = requireAgent(input.agent);
  const taskId = cleanText(input.taskId, 128, "Aufgaben-ID");
  const summary = cleanText(input.summary, MAX_TASK_LENGTH, "Zusammenfassung");
  const row = database.prepare("SELECT * FROM tasks WHERE id = ? AND project_path = ?").get(taskId, canonicalProjectPath(root));
  if (!row) throw new Error("Aufgabe wurde in diesem Projekt nicht gefunden.");
  if (row.owner !== agent) throw new Error("Nur der aktuelle Bearbeiter darf die Aufgabe zum Review einreichen.");
  database.prepare(`
    UPDATE tasks SET status = 'review', summary = ?, updated_at = ? WHERE id = ?
  `).run(summary, now(), taskId);
  postMessage(database, root, {
    sender: agent,
    recipients: AGENTS.filter(value => value !== agent),
    kind: "review_request",
    body: summary,
    roundId: taskId
  });
  return taskFromRow(database.prepare("SELECT * FROM tasks WHERE id = ?").get(taskId));
}

export function reviewTask(database, root, input) {
  const reviewer = requireAgent(input.reviewer);
  const taskId = cleanText(input.taskId, 128, "Aufgaben-ID");
  const verdict = String(input.verdict ?? "").toLowerCase();
  if (!["approved", "changes_requested"].includes(verdict)) throw new Error("Review muss approved oder changes_requested sein.");
  const note = cleanText(input.note, MAX_TASK_LENGTH, "Review-Notiz");
  const row = database.prepare("SELECT * FROM tasks WHERE id = ? AND project_path = ?").get(taskId, canonicalProjectPath(root));
  if (!row) throw new Error("Aufgabe wurde in diesem Projekt nicht gefunden.");
  if (!row.owner) throw new Error("Die Aufgabe hat noch keinen Bearbeiter.");
  if (row.owner === reviewer) throw new Error("Bearbeiter und Reviewer müssen unterschiedliche Agenten sein.");
  if (row.status !== "review") throw new Error("Die Aufgabe wartet derzeit nicht auf ein Review.");
  const nextStatus = verdict === "approved" ? "ready" : "changes_requested";
  const timestamp = now();
  database.exec("BEGIN IMMEDIATE");
  try {
    database.prepare(`
      INSERT INTO reviews(task_id, reviewer, verdict, note, created_at) VALUES (?, ?, ?, ?, ?)
    `).run(taskId, reviewer, verdict, note, timestamp);
    database.prepare(`
      UPDATE tasks SET status = ?, reviewer = ?, updated_at = ? WHERE id = ?
    `).run(nextStatus, reviewer, timestamp, taskId);
    database.exec("COMMIT");
  } catch (error) {
    database.exec("ROLLBACK");
    throw error;
  }
  postMessage(database, root, {
    sender: reviewer,
    recipients: [row.owner],
    kind: "review",
    body: note,
    roundId: taskId
  });
  return taskFromRow(database.prepare("SELECT * FROM tasks WHERE id = ?").get(taskId));
}

export function integrateTask(database, root, input) {
  const integrator = requireAgent(input.agent);
  const taskId = cleanText(input.taskId, 128, "Aufgaben-ID");
  const summary = cleanText(input.summary, MAX_TASK_LENGTH, "Integrationszusammenfassung");
  const row = database.prepare("SELECT * FROM tasks WHERE id = ? AND project_path = ?").get(taskId, canonicalProjectPath(root));
  if (!row) throw new Error("Aufgabe wurde in diesem Projekt nicht gefunden.");
  if (row.status !== "ready") throw new Error("Eine Aufgabe kann erst nach einem fremden, erfolgreichen Review integriert werden.");
  database.prepare(`
    UPDATE tasks SET status = 'done', integrator = ?, summary = ?, updated_at = ? WHERE id = ?
  `).run(integrator, summary, now(), taskId);
  postMessage(database, root, {
    sender: integrator,
    recipients: ["user", ...AGENTS.filter(value => value !== integrator)],
    kind: "integration",
    body: summary,
    roundId: taskId
  });
  return taskFromRow(database.prepare("SELECT * FROM tasks WHERE id = ?").get(taskId));
}

function readProjectFile(root, relativePath) {
  const target = path.join(root, relativePath);
  if (!existsSync(target)) return null;
  return readFileSync(target, "utf8");
}

export function projectDocuments(root) {
  return {
    agents: readProjectFile(root, "AGENTS.md"),
    claude: readProjectFile(root, "CLAUDE.md"),
    rules: readProjectFile(root, "AI_RULES.md"),
    handoff: readProjectFile(root, "AI_HANDOFF.md")
  };
}

export function gitOverview(root) {
  const topLevel = run("git", ["rev-parse", "--show-toplevel"], root);
  if (!topLevel.ok) {
    return { isRepository: false, root, error: topLevel.stderr || topLevel.error || "Kein Git-Repository." };
  }
  const branch = run("git", ["branch", "--show-current"], root);
  const status = run("git", ["status", "--short", "--branch"], root);
  const log = run("git", ["log", "--oneline", "--decorate", "-8"], root);
  const diff = run("git", ["diff", "--stat"], root);
  const staged = run("git", ["diff", "--cached", "--stat"], root);
  const worktrees = run("git", ["worktree", "list", "--porcelain"], root);
  return {
    isRepository: true,
    root: path.resolve(topLevel.stdout),
    branch: branch.stdout || "detached",
    clean: status.stdout.split("\n").slice(1).filter(Boolean).length === 0,
    status: status.stdout,
    diffStat: diff.stdout,
    stagedDiffStat: staged.stdout,
    recentCommits: log.stdout,
    worktrees: worktrees.stdout
  };
}

export function projectAgentStatus(root) {
  const script = path.join(root, "scripts", "agent-status.sh");
  if (existsSync(script)) {
    const result = run(script, ["list"], root);
    return { available: result.ok, source: "scripts/agent-status.sh", text: result.stdout || result.stderr };
  }
  const statuses = [];
  for (const agent of AGENTS) {
    const result = run("git", ["show", `refs/ai-status/${agent}`], root);
    if (result.ok) statuses.push(result.stdout);
  }
  return {
    available: statuses.length > 0,
    source: "refs/ai-status/*",
    text: statuses.join("\n")
  };
}

function templateFiles(project) {
  return {
    "AGENTS.md": `# Agent instructions for ${project}\n\nRead \`AI_RULES.md\` and \`AI_HANDOFF.md\` before larger changes. Use the global Agent Bridge MCP to read the shared state, post messages, create tasks, claim exact files, request peer review, and record integration. Codex and Claude are equal peers. The task owner, reviewer, and integrator are selected per task.\n\nBefore editing, inspect \`git status\`, existing diffs, and active Agent Bridge claims. Never overwrite another agent's or the user's changes.\n`,
    "CLAUDE.md": `# Claude Code instructions for ${project}\n\nRead \`AI_RULES.md\`, \`AI_HANDOFF.md\`, and the global Agent Bridge MCP state before larger changes. Claude and Codex are equal peers. Preserve established architecture unless a change is justified in \`AI_HANDOFF.md\`. Claim exact files before editing and request a peer review before integration.\n`,
    "AI_RULES.md": `# Shared AI rules for ${project}\n\n## Project goal\n\nDocument the verified project goal here after inspecting the repository. Do not invent missing product requirements.\n\n## Architecture and technologies\n\nAnalyze the repository before filling this section. Record only verified architecture, technologies, directories, and commands.\n\n## Change rules\n\n- Read existing code, Git status, diffs, and \`AI_HANDOFF.md\` first.\n- Preserve user changes and the other agent's work.\n- Claim exact files through Agent Bridge before editing.\n- Avoid unnecessary dependencies and broad rewrites.\n- Do not store secrets or credentials in repository files.\n- Require review by the other agent before integration of larger changes.\n\n## Build and tests\n\nDocument verified commands here. Run relevant checks after changes and record exact results in \`AI_HANDOFF.md\`.\n`,
    "AI_HANDOFF.md": `# AI handoff\n\n## Current task\n\nNo active task.\n\n## Relevant changes\n\nNone.\n\n## Open problems\n\nNone known.\n\n## Architecture decisions\n\nAnalyze the repository before recording decisions.\n\n## Outstanding tests\n\nDocument verified commands and results here.\n`
  };
}

export function initializeProject(database, root) {
  registerProject(database, root);
  const created = [];
  const preserved = [];
  for (const [relativePath, content] of Object.entries(templateFiles(projectName(root)))) {
    const target = path.join(root, relativePath);
    if (existsSync(target)) {
      preserved.push(relativePath);
      continue;
    }
    writeFileSync(target, content, { encoding: "utf8", flag: "wx" });
    created.push(relativePath);
  }
  return { root, created, preserved };
}

export function commandAvailability() {
  const check = command => run("/usr/bin/which", [command], process.cwd());
  const node = check("node");
  const codex = check("codex");
  const claude = check("claude");
  return {
    node: { available: node.ok, path: node.stdout },
    codex: { available: codex.ok, path: codex.stdout },
    claude: { available: claude.ok, path: claude.stdout }
  };
}

export function bridgeState(database, root, options = {}) {
  return {
    project: registerProject(database, root),
    git: gitOverview(root),
    agents: projectAgentStatus(root),
    tasks: listTasks(database, root, { includeDone: Boolean(options.includeDone) }),
    messages: listMessages(database, root, { limit: options.messageLimit ?? 150 }),
    commands: commandAvailability(),
    documents: Object.fromEntries(
      Object.entries(projectDocuments(root)).map(([key, value]) => [key, value !== null])
    ),
    generatedAt: now()
  };
}

export function closeStore(database) {
  database.close();
}
