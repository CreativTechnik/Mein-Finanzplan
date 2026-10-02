import { randomBytes, randomUUID } from "node:crypto";
import { createReadStream, existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn, spawnSync } from "node:child_process";
import {
  AGENTS,
  bridgeState,
  claimTask,
  createTask,
  initializeProject,
  integrateTask,
  listMessages,
  openStore,
  postMessage,
  resolveProjectRoot,
  reviewTask,
  submitTaskForReview
} from "./core.mjs";

const moduleDirectory = path.dirname(fileURLToPath(import.meta.url));
const uiFile = path.resolve(moduleDirectory, "..", "ui", "index.html");
const MAX_BODY_BYTES = 64 * 1024;
const MAX_PROCESS_OUTPUT = 2 * 1024 * 1024;
const AGENT_TIMEOUT_MS = 10 * 60 * 1000;

function json(response, status, value) {
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'"
  });
  response.end(JSON.stringify(value));
}

function readJson(request) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    request.on("data", chunk => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        reject(new Error("Anfrage ist zu groß."));
        request.destroy();
        return;
      }
      chunks.push(chunk);
    });
    request.on("end", () => {
      try {
        const raw = Buffer.concat(chunks).toString("utf8");
        resolve(raw ? JSON.parse(raw) : {});
      } catch {
        reject(new Error("Ungültiges JSON."));
      }
    });
    request.on("error", reject);
  });
}

function isLocalHost(request) {
  const host = String(request.headers.host ?? "").split(":")[0];
  return host === "127.0.0.1" || host === "localhost" || host === "[::1]";
}

function isAllowedOrigin(request, port) {
  const origin = request.headers.origin;
  if (!origin) return true;
  return origin === `http://127.0.0.1:${port}` || origin === `http://localhost:${port}`;
}

function runProcess(command, args, cwd, timeout = AGENT_TIMEOUT_MS) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      env: { ...process.env, AGENT_BRIDGE_PROJECT_ROOT: cwd },
      stdio: ["ignore", "pipe", "pipe"]
    });
    let stdout = "";
    let stderr = "";
    let finished = false;
    const timer = setTimeout(() => {
      if (finished) return;
      child.kill("SIGTERM");
      setTimeout(() => child.kill("SIGKILL"), 2_000).unref();
    }, timeout);

    const append = (current, chunk) => {
      const next = current + chunk.toString("utf8");
      return next.length > MAX_PROCESS_OUTPUT ? next.slice(-MAX_PROCESS_OUTPUT) : next;
    };
    child.stdout.on("data", chunk => { stdout = append(stdout, chunk); });
    child.stderr.on("data", chunk => { stderr = append(stderr, chunk); });
    child.on("error", error => {
      finished = true;
      clearTimeout(timer);
      reject(error);
    });
    child.on("close", (code, signal) => {
      finished = true;
      clearTimeout(timer);
      resolve({ code, signal, stdout, stderr });
    });
  });
}

function transcript(database, root) {
  return listMessages(database, root, { limit: 28 }).map(message => {
    const label = message.sender === "user" ? "Nutzer" : message.sender === "system" ? "System" : message.sender;
    return `${label}: ${message.body}`;
  }).join("\n\n");
}

function deliberationPrompt(agent, database, root, userMessage, reviewContext = null) {
  const other = agent === "codex" ? "Claude" : "Codex";
  const history = transcript(database, root);
  const reviewInstruction = reviewContext
    ? `\n\nPrüfe jetzt als gleichrangiger Peer die folgende Antwort von ${other}. Benenne Übereinstimmungen, Risiken und einen besseren gemeinsamen Vorschlag:\n\n${reviewContext}`
    : "";
  return `Du bist ${agent === "codex" ? "Codex" : "Claude"} in Agent Bridge. Codex und Claude sind gleichrangige technische Peers. Dies ist eine schreibgeschützte Beratungsrunde. Verändere keine Dateien und starte keine mutierenden Befehle. Lies bei Bedarf AGENTS.md, CLAUDE.md, AI_RULES.md und AI_HANDOFF.md. Antworte auf Deutsch, konkret und knapp. Ergänze die andere Perspektive, statt Hierarchie zu beanspruchen. Für spätere Implementierung gelten Datei-Claims, getrennte Worktrees, gegenseitiges Review und konfliktfreie Integration.\n\nGemeinsame Unterhaltung:\n${history || "Noch keine Nachrichten."}\n\nAktuelle Bitte des Nutzers:\n${userMessage}${reviewInstruction}`;
}

async function runCodex(root, prompt) {
  const temporary = mkdtempSync(path.join(tmpdir(), "agent-bridge-codex-"));
  const outputFile = path.join(temporary, "answer.txt");
  try {
    const result = await runProcess("codex", [
      "--ask-for-approval", "never",
      "--sandbox", "read-only",
      "-C", root,
      "exec",
      "--ephemeral",
      "--color", "never",
      "--output-last-message", outputFile,
      prompt
    ], root);
    const answer = existsSync(outputFile) ? readFileSync(outputFile, "utf8").trim() : "";
    if (result.code !== 0 || !answer) {
      throw new Error(result.stderr.trim() || `Codex wurde mit Status ${result.code ?? result.signal} beendet.`);
    }
    return answer;
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
}

async function runClaude(root, prompt) {
  const result = await runProcess("claude", [
    "-p",
    "--no-session-persistence",
    "--output-format", "json",
    "--permission-mode", "dontAsk",
    "--tools", "Read,Glob,Grep",
    "--",
    prompt
  ], root);
  if (result.code !== 0) {
    throw new Error(result.stderr.trim() || `Claude wurde mit Status ${result.code ?? result.signal} beendet.`);
  }
  let parsed;
  try {
    parsed = JSON.parse(result.stdout);
  } catch {
    throw new Error("Claude hat keine lesbare JSON-Antwort geliefert.");
  }
  const answer = String(parsed.result ?? "").trim();
  if (!answer) throw new Error("Claude hat eine leere Antwort geliefert.");
  return answer;
}

async function runAgent(agent, root, prompt) {
  return agent === "codex" ? runCodex(root, prompt) : runClaude(root, prompt);
}

function openBrowser(url) {
  const command = process.platform === "darwin" ? "open" : process.platform === "win32" ? "cmd" : "xdg-open";
  const args = process.platform === "win32" ? ["/c", "start", "", url] : [url];
  spawnSync(command, args, { stdio: "ignore" });
}

export async function startDashboard(options = {}) {
  const root = resolveProjectRoot(options.root);
  const port = Number(options.port ?? 47831);
  if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error("Port muss zwischen 1024 und 65535 liegen.");
  const database = openStore();
  const csrfToken = randomBytes(24).toString("hex");
  const sessionPrefix = `/session/${csrfToken}`;
  const dashboardUrl = `http://127.0.0.1:${port}${sessionPrefix}/`;
  const clients = new Set();
  const activeRuns = new Map();

  const state = () => ({
    ...bridgeState(database, root, { includeDone: true, messageLimit: 200 }),
    runtime: {
      activeRuns: [...activeRuns.entries()].map(([agent, value]) => ({ agent, ...value })),
      url: dashboardUrl
    },
    csrfToken
  });

  const broadcast = () => {
    const payload = `event: state\ndata: ${JSON.stringify(state())}\n\n`;
    for (const client of clients) client.write(payload);
  };

  const dispatch = async ({ body, targets, kind = "chat", reviewByAgent = {} }) => {
    const roundId = randomUUID();
    await Promise.all(targets.map(async agent => {
      activeRuns.set(agent, { roundId, startedAt: new Date().toISOString(), kind });
      broadcast();
      try {
        const prompt = deliberationPrompt(agent, database, root, body, reviewByAgent[agent] ?? null);
        const answer = await runAgent(agent, root, prompt);
        postMessage(database, root, {
          sender: agent,
          recipients: ["user", ...AGENTS.filter(value => value !== agent)],
          kind,
          body: answer,
          roundId
        });
      } catch (error) {
        postMessage(database, root, {
          sender: "system",
          recipients: ["user"],
          kind: "error",
          body: `${agent === "codex" ? "Codex" : "Claude"}: ${error instanceof Error ? error.message : String(error)}`,
          roundId
        });
      } finally {
        activeRuns.delete(agent);
        broadcast();
      }
    }));
  };

  const requireIdleAgents = targets => {
    const busy = targets.filter(agent => activeRuns.has(agent));
    if (busy.length) {
      const names = busy.map(agent => agent === "codex" ? "Codex" : "Claude").join(", ");
      throw new Error(`${names} arbeitet bereits. Warte auf die laufende Antwort.`);
    }
  };

  const server = createServer(async (request, response) => {
    try {
      if (!isLocalHost(request)) return json(response, 403, { error: "Nur lokale Zugriffe sind erlaubt." });
      if (!isAllowedOrigin(request, port)) return json(response, 403, { error: "Unerlaubter Ursprung." });

      const url = new URL(request.url ?? "/", `http://127.0.0.1:${port}`);
      if (request.method === "GET" && url.pathname === "/health") return json(response, 200, { ok: true, root });
      if (url.pathname !== sessionPrefix && !url.pathname.startsWith(`${sessionPrefix}/`)) {
        return json(response, 404, { error: "Nicht gefunden." });
      }
      const routePath = url.pathname.slice(sessionPrefix.length) || "/";

      if (request.method === "GET" && routePath === "/") {
        response.writeHead(200, {
          "Content-Type": "text/html; charset=utf-8",
          "Cache-Control": "no-store",
          "X-Content-Type-Options": "nosniff",
          "Referrer-Policy": "no-referrer",
          "Content-Security-Policy": "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
        });
        createReadStream(uiFile).pipe(response);
        return;
      }
      if (request.method === "GET" && routePath === "/api/state") return json(response, 200, state());
      if (request.method === "GET" && routePath === "/api/events") {
        response.writeHead(200, {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-store",
          "Connection": "keep-alive",
          "X-Accel-Buffering": "no"
        });
        clients.add(response);
        response.write(`event: state\ndata: ${JSON.stringify(state())}\n\n`);
        const keepAlive = setInterval(() => response.write(": keep-alive\n\n"), 15_000);
        request.on("close", () => {
          clearInterval(keepAlive);
          clients.delete(response);
        });
        return;
      }
      if (request.method !== "POST") return json(response, 404, { error: "Nicht gefunden." });
      if (request.headers["x-agent-bridge-token"] !== csrfToken) return json(response, 403, { error: "Ungültiges Sitzungstoken." });
      const input = await readJson(request);

      if (routePath === "/api/message") {
        const message = postMessage(database, root, {
          sender: "user",
          recipients: input.targets ?? ["codex", "claude"],
          body: input.body,
          kind: "chat"
        });
        broadcast();
        return json(response, 201, { message });
      }

      if (routePath === "/api/chat") {
        const targets = [...new Set((input.targets ?? AGENTS).filter(agent => AGENTS.includes(agent)))];
        if (!targets.length) throw new Error("Wähle mindestens einen Agenten aus.");
        requireIdleAgents(targets);
        const message = postMessage(database, root, {
          sender: "user",
          recipients: targets,
          body: input.body,
          kind: "chat"
        });
        broadcast();
        void dispatch({ body: message.body, targets });
        return json(response, 202, { message, targets });
      }

      if (routePath === "/api/peer-review") {
        requireIdleAgents(AGENTS);
        const messages = listMessages(database, root, { limit: 100 });
        const lastCodex = [...messages].reverse().find(message => message.sender === "codex" && message.kind !== "peer_review");
        const lastClaude = [...messages].reverse().find(message => message.sender === "claude" && message.kind !== "peer_review");
        if (!lastCodex || !lastClaude) throw new Error("Für ein Peer-Review wird zuerst je eine Antwort von Codex und Claude benötigt.");
        const body = String(input.body ?? "Erarbeitet eine gemeinsame, belastbare Empfehlung.");
        void dispatch({
          body,
          targets: AGENTS,
          kind: "peer_review",
          reviewByAgent: { codex: lastClaude.body, claude: lastCodex.body }
        });
        return json(response, 202, { ok: true });
      }

      if (routePath === "/api/project/init") {
        const result = initializeProject(database, root);
        broadcast();
        return json(response, 200, result);
      }

      if (routePath === "/api/tasks") {
        const task = createTask(database, root, {
          title: input.title,
          description: input.description,
          files: input.files ?? [],
          createdBy: "user"
        });
        broadcast();
        return json(response, 201, { task });
      }

      const taskMatch = routePath.match(/^\/api\/tasks\/([^/]+)\/(claim|submit|review|integrate)$/);
      if (taskMatch) {
        const taskId = decodeURIComponent(taskMatch[1]);
        const action = taskMatch[2];
        let task;
        if (action === "claim") task = claimTask(database, root, { taskId, agent: input.agent, files: input.files ?? [] });
        if (action === "submit") task = submitTaskForReview(database, root, { taskId, agent: input.agent, summary: input.summary });
        if (action === "review") task = reviewTask(database, root, { taskId, reviewer: input.reviewer, verdict: input.verdict, note: input.note });
        if (action === "integrate") task = integrateTask(database, root, { taskId, agent: input.agent, summary: input.summary });
        broadcast();
        return json(response, 200, { task });
      }

      return json(response, 404, { error: "Nicht gefunden." });
    } catch (error) {
      return json(response, 400, { error: error instanceof Error ? error.message : String(error) });
    }
  });

  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, "127.0.0.1", resolve);
  });

  if (options.open !== false) openBrowser(dashboardUrl);
  return {
    root,
    port,
    url: dashboardUrl,
    close: () => new Promise(resolve => server.close(resolve))
  };
}
