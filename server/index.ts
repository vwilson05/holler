/**
 * Holler — Walkie-Talkie Relay Server
 *
 * Bun + Hono HTTP endpoints with native Bun WebSocket for real-time relay.
 * All voice/location data is ephemeral — relayed and forgotten.
 *
 * Connect: ws://host/ws?room=ROOM_CODE&id=DEVICE_UUID&name=DISPLAY_NAME
 * Deploy:  railway up
 */

import { Hono } from "hono";
import { cors } from "hono/cors";
import type { ConnectParams } from "./types";
import {
  handleJoin,
  handleDisconnect,
  handleMessage,
  getStats,
  getDetailedStats,
  getRoomList,
  isValidRoomCode,
} from "./room";

const PORT = parseInt(process.env.PORT || "3000");

// --- Hono App (HTTP routes) ---

const app = new Hono();

app.use("*", cors());

// Serve Apple App Site Association for Universal Links
app.get("/.well-known/apple-app-site-association", async (c) => {
  const aasaPath = new URL("./public/.well-known/apple-app-site-association", import.meta.url).pathname;
  const file = Bun.file(aasaPath);
  if (await file.exists()) {
    return c.json(JSON.parse(await file.text()));
  }
  return c.json({ error: "AASA not found" }, 404);
});

// /join redirect — if user hits this without the iOS app, redirect to web client on relay
app.get("/join", (c) => {
  const g = c.req.query("g") || "";
  const p = c.req.query("p") || "";
  const host = c.req.header("host") || "";
  const isRelay = host.includes("holler-relay-production");
  // If on relay server, redirect to root (web client). If on landing page domain, redirect to relay.
  const relayURL = isRelay
    ? `/?g=${encodeURIComponent(g)}&p=${encodeURIComponent(p)}`
    : `https://holler-relay-production.up.railway.app/?g=${encodeURIComponent(g)}&p=${encodeURIComponent(p)}`;
  return c.redirect(relayURL);
});

app.get("/", async (c) => {
  // Serve the web client
  const webPath = new URL("../web/index.html", import.meta.url).pathname;
  const file = Bun.file(webPath);
  if (await file.exists()) {
    return c.html(await file.text());
  }
  // Fallback if web client not found
  const stats = getStats();
  return c.text(
    `Holler Relay Server\n\n` +
      `Rooms: ${stats.rooms}\n` +
      `Connections: ${stats.connections}\n` +
      `Connect: ws://${c.req.header("host") || "localhost:" + PORT}/ws?room=ROOM&id=ID&name=NAME\n`
  );
});

app.get("/test", async (c) => {
  const testPath = new URL("../web/test.html", import.meta.url).pathname;
  const file = Bun.file(testPath);
  if (await file.exists()) return c.html(await file.text());
  return c.text("test.html not found", 404);
});

app.get("/health", (c) => {
  return c.json(getStats());
});

app.get("/rooms", (c) => {
  return c.json({ rooms: getRoomList() });
});

app.get("/stats", (c) => {
  return c.json(getDetailedStats());
});

// --- Bun Server with WebSocket ---

const server = Bun.serve({
  port: PORT,
  fetch(req, server) {
    const url = new URL(req.url);

    // WebSocket upgrade on /ws
    if (url.pathname === "/ws") {
      const room = url.searchParams.get("room");
      const id = url.searchParams.get("id");
      const name = url.searchParams.get("name");

      if (!room || !id || !name) {
        return new Response(
          JSON.stringify({ error: "Missing required query params: room, id, name" }),
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
      }

      if (!isValidRoomCode(room)) {
        return new Response(
          JSON.stringify({ error: "Invalid room code. Must be 3-32 alphanumeric/hyphen characters." }),
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
      }

      const success = server.upgrade(req, {
        data: { room, id, name } satisfies ConnectParams,
      });

      if (success) return undefined;
      return new Response(
        JSON.stringify({ error: "WebSocket upgrade failed" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    // Delegate all other routes to Hono
    return app.fetch(req);
  },

  websocket: {
    maxPayloadLength: 2 * 1024 * 1024, // 2MB max
    idleTimeout: 120, // 2 min idle timeout (heartbeat keeps alive)

    open(ws) {
      const params = ws.data as ConnectParams;
      const result = handleJoin(ws, params);
      if (result.error) {
        try {
          ws.send(JSON.stringify({ type: "error", payload: { message: result.error } }));
          ws.close(1008, result.error);
        } catch {}
      }
    },

    message(ws, message) {
      handleMessage(ws, message as string | Buffer);
    },

    close(ws) {
      handleDisconnect(ws);
    },
  },
});

console.log(`[holler] relay server running on port ${PORT}`);
