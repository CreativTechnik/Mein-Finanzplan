#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/server";
import { serveStdio } from "@modelcontextprotocol/server/stdio";
import * as z from "zod/v4";
import {
  AGENTS,
  bridgeState,
  claimTask,
  createTask,
  gitOverview,
  initializeProject,
  integrateTask,
  listMessages,
  openStore,
  postMessage,
  projectDocuments,
  resolveProjectRoot,
  reviewTask,
  submitTaskForReview
} from "./core.mjs";

const projectRoot = resolveProjectRoot();

function textResult(value) {
  return {
    content: [{ type: "text", text: JSON.stringify(value, null, 2) }]
  };
}

function errorResult(error) {
  return {
    isError: true,
    content: [{ type: "text", text: error instanceof Error ? error.message : String(error) }]
  };
}

function safe(handler) {
  return async input => {
    try {
      return textResult(await handler(input));
    } catch (error) {
      return errorResult(error);
    }
  };
}

function buildServer() {
  const database = openStore();
  const server = new McpServer({
    name: "creativtechnik-agent-bridge",
    version: "0.1.0"
  });

  server.registerResource(
    "shared-rules",
    "agent-bridge://project/rules",
    {
      title: "Shared AI rules",
      description: "Verified project rules shared by Codex and Claude.",
      mimeType: "text/markdown"
    },
    async uri => ({
      contents: [{
        uri: uri.href,
        mimeType: "text/markdown",
        text: projectDocuments(projectRoot).rules ?? "AI_RULES.md fehlt. Initialisiere das Projekt zuerst."
      }]
    })
  );

  server.registerResource(
    "shared-handoff",
    "agent-bridge://project/handoff",
    {
      title: "Shared AI handoff",
      description: "Current task, decisions, changes, blockers, and outstanding tests.",
      mimeType: "text/markdown"
    },
    async uri => ({
      contents: [{
        uri: uri.href,
        mimeType: "text/markdown",
        text: projectDocuments(projectRoot).handoff ?? "AI_HANDOFF.md fehlt. Initialisiere das Projekt zuerst."
      }]
    })
  );

  server.registerResource(
    "live-state",
    "agent-bridge://project/state",
    {
      title: "Agent Bridge live state",
      description: "Git, agent, task, and message state for the current project.",
      mimeType: "application/json"
    },
    async uri => ({
      contents: [{
        uri: uri.href,
        mimeType: "application/json",
        text: JSON.stringify(bridgeState(database, projectRoot), null, 2)
      }]
    })
  );

  server.registerTool(
    "bridge_status",
    {
      title: "Read project coordination state",
      description: "Returns Git status, agent claims, open tasks, messages, and coordination files for the current project.",
      inputSchema: z.object({
        includeDone: z.boolean().optional().default(false),
        messageLimit: z.number().int().min(1).max(500).optional().default(100)
      }),
      annotations: { readOnlyHint: true, destructiveHint: false }
    },
    safe(({ includeDone, messageLimit }) => bridgeState(database, projectRoot, { includeDone, messageLimit }))
  );

  server.registerTool(
    "git_overview",
    {
      title: "Read Git overview",
      description: "Returns branch, worktree, diff, and recent commit information without changing Git state.",
      inputSchema: z.object({}),
      annotations: { readOnlyHint: true, destructiveHint: false }
    },
    safe(() => gitOverview(projectRoot))
  );

  server.registerTool(
    "get_messages",
    {
      title: "Read shared messages",
      description: "Reads the shared project conversation visible to the requested participant.",
      inputSchema: z.object({
        agent: z.enum(["codex", "claude", "user", "all"]).optional().default("all"),
        afterId: z.number().int().nonnegative().optional().default(0),
        limit: z.number().int().min(1).max(500).optional().default(100)
      }),
      annotations: { readOnlyHint: true, destructiveHint: false }
    },
    safe(({ agent, afterId, limit }) => listMessages(database, projectRoot, { agent, afterId, limit }))
  );

  server.registerTool(
    "post_message",
    {
      title: "Post shared message",
      description: "Posts a message to Codex, Claude, the user, or both agents in the current project's shared conversation.",
      inputSchema: z.object({
        sender: z.enum(["user", "codex", "claude", "system"]),
        recipients: z.array(z.enum(["codex", "claude", "user", "all"])).min(1),
        body: z.string().min(1).max(20_000),
        kind: z.string().min(1).max(64).optional().default("chat"),
        roundId: z.string().max(128).optional()
      }),
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false }
    },
    safe(input => postMessage(database, projectRoot, input))
  );

  server.registerTool(
    "create_task",
    {
      title: "Create peer task",
      description: "Creates an unassigned task. Codex and Claude remain equal until one claims the task and the other reviews it.",
      inputSchema: z.object({
        title: z.string().min(1).max(300),
        description: z.string().min(1).max(8_000),
        files: z.array(z.string().min(1)).optional().default([]),
        createdBy: z.enum(["user", "codex", "claude", "system"]).optional().default("user")
      }),
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false }
    },
    safe(input => createTask(database, projectRoot, input))
  );

  server.registerTool(
    "claim_task",
    {
      title: "Claim task and files",
      description: "Claims a task for one agent and rejects overlapping file claims from active tasks.",
      inputSchema: z.object({
        taskId: z.string().min(1),
        agent: z.enum(AGENTS),
        files: z.array(z.string().min(1)).optional().default([])
      }),
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true }
    },
    safe(input => claimTask(database, projectRoot, input))
  );

  server.registerTool(
    "submit_for_review",
    {
      title: "Submit work for peer review",
      description: "Moves an owned task into review and notifies the other equal peer.",
      inputSchema: z.object({
        taskId: z.string().min(1),
        agent: z.enum(AGENTS),
        summary: z.string().min(1).max(8_000)
      }),
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true }
    },
    safe(input => submitTaskForReview(database, projectRoot, input))
  );

  server.registerTool(
    "review_task",
    {
      title: "Review peer work",
      description: "Records approval or requested changes. The reviewer must be the other agent.",
      inputSchema: z.object({
        taskId: z.string().min(1),
        reviewer: z.enum(AGENTS),
        verdict: z.enum(["approved", "changes_requested"]),
        note: z.string().min(1).max(8_000)
      }),
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false }
    },
    safe(input => reviewTask(database, projectRoot, input))
  );

  server.registerTool(
    "integrate_task",
    {
      title: "Record reviewed integration",
      description: "Marks a peer-approved task complete and records which agent performed integration.",
      inputSchema: z.object({
        taskId: z.string().min(1),
        agent: z.enum(AGENTS),
        summary: z.string().min(1).max(8_000)
      }),
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true }
    },
    safe(input => integrateTask(database, projectRoot, input))
  );

  server.registerTool(
    "initialize_project",
    {
      title: "Initialize shared agent files",
      description: "Creates missing AGENTS.md, CLAUDE.md, AI_RULES.md, and AI_HANDOFF.md without overwriting existing files.",
      inputSchema: z.object({}),
      annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true }
    },
    safe(() => initializeProject(database, projectRoot))
  );

  server.registerPrompt(
    "equal-peer-workflow",
    {
      title: "Equal peer workflow",
      description: "Starts a task with equal Codex and Claude roles, file claims, peer review, and safe integration.",
      argsSchema: z.object({
        task: z.string().min(1),
        agent: z.enum(AGENTS)
      })
    },
    ({ task, agent }) => ({
      messages: [{
        role: "user",
        content: {
          type: "text",
          text: `You are ${agent}, one of two equal peers. Read agent-bridge://project/rules, agent-bridge://project/handoff, and bridge_status first. Discuss the task through post_message when another perspective helps. Create or claim exact files before editing. Preserve user and peer changes. Submit completed work through submit_for_review; the other agent reviews it before either peer records integration. Task: ${task}`
        }
      }]
    })
  );

  return server;
}

serveStdio(buildServer);
