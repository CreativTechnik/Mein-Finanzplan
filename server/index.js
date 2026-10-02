import { buildApp } from "./app.js";

const port = Number(process.env.PORT ?? 4178);
const host = process.env.HOST ?? "127.0.0.1";
const app = await buildApp({ logger: process.env.LOG_LEVEL ? { level: process.env.LOG_LEVEL } : false });

const address = await app.listen({ port, host });
console.log(`Finanzplan läuft unter ${address}`);

async function shutdown() {
  await app.close();
  process.exit(0);
}

process.once("SIGINT", shutdown);
process.once("SIGTERM", shutdown);
