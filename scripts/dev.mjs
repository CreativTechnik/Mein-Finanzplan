import { spawn } from "node:child_process";

const children = [
  spawn(process.execPath, ["--watch", "server/index.js"], { stdio: "inherit" }),
  spawn("npx", ["vite", "--host", "127.0.0.1"], { stdio: "inherit" }),
];

function stop(signal = "SIGTERM") {
  for (const child of children) child.kill(signal);
}

process.once("SIGINT", () => stop("SIGINT"));
process.once("SIGTERM", () => stop("SIGTERM"));
await Promise.all(children.map((child) => new Promise((resolve) => child.once("exit", resolve))));
