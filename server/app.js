import fastify from "fastify";
import fastifyStatic from "@fastify/static";
import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { createDatabase } from "./db.js";
import { registerRoutes } from "./routes.js";

export async function buildApp(options = {}) {
  const database = options.database ?? createDatabase({ path: options.databasePath });
  const app = fastify({
    logger: options.logger ?? false,
    bodyLimit: 1_500_000,
    requestTimeout: 15_000,
    keepAliveTimeout: 5_000,
  });

  app.addHook("onSend", async (_request, reply, payload) => {
    reply.header("X-Content-Type-Options", "nosniff");
    reply.header("Referrer-Policy", "no-referrer");
    reply.header("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
    return payload;
  });

  await registerRoutes(app, database);

  const distPath = resolve("dist");
  if (options.serveStatic !== false && existsSync(distPath)) {
    await app.register(fastifyStatic, {
      root: distPath,
      wildcard: false,
      index: false,
      maxAge: "30d",
      immutable: true,
      serveDotFiles: false,
    });
    app.get("/", async (_request, reply) => reply.sendFile("index.html", { maxAge: 0, immutable: false }));
    app.setNotFoundHandler(async (request, reply) => {
      if (request.url.startsWith("/api/")) return reply.code(404).send({ error: "API-Endpunkt nicht gefunden." });
      return reply.sendFile("index.html", { maxAge: 0, immutable: false });
    });
  }

  app.setErrorHandler((error, _request, reply) => {
    const statusCode = Number(error.statusCode) >= 400 && Number(error.statusCode) < 600 ? Number(error.statusCode) : 500;
    if (statusCode >= 500 && options.logger) app.log.error(error);
    reply.code(statusCode).send({ error: statusCode >= 500 ? "Die Anfrage konnte nicht verarbeitet werden." : error.message });
  });

  app.addHook("onClose", async () => {
    if (!options.database) database.close();
  });
  app.decorate("financeDatabase", database);
  return app;
}
