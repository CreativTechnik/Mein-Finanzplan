import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import {
  claimTask,
  closeStore,
  createTask,
  initializeProject,
  integrateTask,
  listMessages,
  listTasks,
  normalizeFiles,
  openStore,
  postMessage,
  reviewTask,
  submitTaskForReview
} from "../src/core.mjs";

function fixture() {
  const directory = mkdtempSync(path.join(tmpdir(), "agent-bridge-core-"));
  const root = path.join(directory, "project");
  mkdirSync(root);
  const database = openStore(path.join(directory, "state.sqlite"));
  return {
    directory,
    root,
    database,
    close() {
      closeStore(database);
      rmSync(directory, { recursive: true, force: true });
    }
  };
}

test("initialization creates only missing collaboration files", () => {
  const context = fixture();
  try {
    writeFileSync(path.join(context.root, "AGENTS.md"), "existing rules\n");
    const first = initializeProject(context.database, context.root);
    assert.deepEqual(first.preserved, ["AGENTS.md"]);
    assert.deepEqual(first.created.sort(), ["AI_HANDOFF.md", "AI_RULES.md", "CLAUDE.md"]);
    assert.equal(readFileSync(path.join(context.root, "AGENTS.md"), "utf8"), "existing rules\n");

    const second = initializeProject(context.database, context.root);
    assert.deepEqual(second.created, []);
    assert.deepEqual(second.preserved.sort(), ["AGENTS.md", "AI_HANDOFF.md", "AI_RULES.md", "CLAUDE.md"]);
  } finally {
    context.close();
  }
});

test("messages are project scoped and filtered per participant", () => {
  const context = fixture();
  try {
    postMessage(context.database, context.root, {
      sender: "user",
      recipients: ["codex"],
      body: "Nur für Codex"
    });
    postMessage(context.database, context.root, {
      sender: "claude",
      recipients: ["user", "codex"],
      body: "Gemeinsamer Hinweis"
    });

    assert.deepEqual(listMessages(context.database, context.root, { agent: "claude" }).map(item => item.body), ["Gemeinsamer Hinweis"]);
    assert.deepEqual(listMessages(context.database, context.root, { agent: "codex" }).map(item => item.body), ["Nur für Codex", "Gemeinsamer Hinweis"]);
    assert.deepEqual(listMessages(context.database, path.join(context.root, "other")).map(item => item.body), []);
  } finally {
    context.close();
  }
});

test("task ownership prevents overlapping edits and requires peer review", () => {
  const context = fixture();
  try {
    const first = createTask(context.database, context.root, {
      title: "Implement bridge",
      description: "Add the shared bridge.",
      files: ["src", "README.md"]
    });
    const second = createTask(context.database, context.root, {
      title: "Edit server",
      description: "Touch the MCP server.",
      files: ["src/server.mjs"]
    });

    const active = claimTask(context.database, context.root, { taskId: first.id, agent: "codex" });
    assert.equal(active.status, "active");
    assert.equal(active.owner, "codex");
    assert.throws(
      () => claimTask(context.database, context.root, { taskId: second.id, agent: "claude" }),
      /Dateikonflikt/
    );

    const review = submitTaskForReview(context.database, context.root, {
      taskId: first.id,
      agent: "codex",
      summary: "Implemented and tested."
    });
    assert.equal(review.status, "review");
    assert.throws(
      () => reviewTask(context.database, context.root, {
        taskId: first.id,
        reviewer: "codex",
        verdict: "approved",
        note: "Self approval"
      }),
      /unterschiedliche Agenten/
    );

    const ready = reviewTask(context.database, context.root, {
      taskId: first.id,
      reviewer: "claude",
      verdict: "approved",
      note: "Peer review passed."
    });
    assert.equal(ready.status, "ready");
    assert.equal(ready.reviewer, "claude");

    const done = integrateTask(context.database, context.root, {
      taskId: first.id,
      agent: "claude",
      summary: "Integrated after review."
    });
    assert.equal(done.status, "done");
    assert.equal(done.integrator, "claude");
    assert.equal(listTasks(context.database, context.root).length, 1);
    assert.equal(listTasks(context.database, context.root, { includeDone: true }).length, 2);
  } finally {
    context.close();
  }
});

test("file claims accept normalized relative paths only", () => {
  assert.deepEqual(normalizeFiles(["src\\server.mjs", "src/server.mjs", "docs/readme.md"]), ["docs/readme.md", "src/server.mjs"]);
  assert.throws(() => normalizeFiles(["../outside.txt"]), /Ungültiger/);
  assert.throws(() => normalizeFiles(["/absolute.txt"]), /Ungültiger/);
});

test("linked Git worktrees share messages and file claims", () => {
  const directory = mkdtempSync(path.join(tmpdir(), "agent-bridge-worktree-"));
  const root = path.join(directory, "main");
  const linked = path.join(directory, "linked");
  mkdirSync(root);
  execFileSync("git", ["init", "-q"], { cwd: root });
  execFileSync("git", ["-c", "user.name=Agent Bridge", "-c", "user.email=agent-bridge@example.invalid", "commit", "--allow-empty", "-qm", "initial"], { cwd: root });
  execFileSync("git", ["worktree", "add", "-qb", "linked-test", linked], { cwd: root });
  const database = openStore(path.join(directory, "state.sqlite"));

  try {
    postMessage(database, root, { sender: "codex", recipients: ["claude"], body: "Shared across worktrees" });
    assert.equal(listMessages(database, linked).at(-1).body, "Shared across worktrees");

    const first = createTask(database, root, {
      title: "Main task",
      description: "Claim from main worktree.",
      files: ["src/shared.mjs"]
    });
    claimTask(database, root, { taskId: first.id, agent: "codex" });
    const second = createTask(database, linked, {
      title: "Linked task",
      description: "Conflicting claim from linked worktree.",
      files: ["src/shared.mjs"]
    });
    assert.throws(
      () => claimTask(database, linked, { taskId: second.id, agent: "claude" }),
      /Dateikonflikt/
    );
  } finally {
    closeStore(database);
    rmSync(directory, { recursive: true, force: true });
  }
});
