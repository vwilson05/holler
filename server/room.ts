/**
 * Holler Relay Server — Room Management
 *
 * Ephemeral in-memory rooms. No persistence, no logs of content.
 * Rooms auto-delete 1 hour after last member disconnects.
 */

import type { ServerWebSocket } from "bun";
import type { WireMessage, MemberInfo, LocationPayload, ConnectParams } from "./types";

const MAX_MEMBERS = 50;
const ROOM_TTL_MS = 60 * 60 * 1000; // 1 hour
const HEARTBEAT_TIMEOUT_MS = 60_000; // 60s no ping = offline
const RATE_LIMIT_WINDOW_MS = 60_000; // 1 minute
const RATE_LIMIT_MAX = 60; // max messages per window
const MAX_PAYLOAD_BYTES = 2 * 1024 * 1024; // 2MB

// Room code: alphanumeric + hyphens, 3-32 chars
const ROOM_CODE_RE = /^[a-zA-Z0-9-]{3,32}$/;

export interface Client {
  ws: ServerWebSocket<ConnectParams>;
  id: string;
  name: string;
  room: string;
  joinedAt: number;
  lastPing: number;
  online: boolean;
  location: LocationPayload | null;
  messageTimestamps: number[]; // for rate limiting
}

export interface RoomState {
  code: string;
  clients: Map<string, Client>; // keyed by device id
  createdAt: number;
  cleanupTimer: ReturnType<typeof setTimeout> | null;
}

// Global metrics
let totalMessagesRelayed = 0;
let peakConnections = 0;
let currentConnections = 0;

/** All active rooms */
const rooms = new Map<string, RoomState>();

// --- Validation ---

export function isValidRoomCode(code: string): boolean {
  return ROOM_CODE_RE.test(code);
}

// --- Rate Limiting ---

function checkRateLimit(client: Client): boolean {
  const now = Date.now();
  // Purge old timestamps
  client.messageTimestamps = client.messageTimestamps.filter(
    (t) => now - t < RATE_LIMIT_WINDOW_MS
  );
  if (client.messageTimestamps.length >= RATE_LIMIT_MAX) {
    return false; // rate limited
  }
  client.messageTimestamps.push(now);
  return true;
}

// --- Room Lifecycle ---

function getOrCreateRoom(code: string): RoomState {
  let room = rooms.get(code);
  if (!room) {
    room = {
      code,
      clients: new Map(),
      createdAt: Date.now(),
      cleanupTimer: null,
    };
    rooms.set(code, room);
    console.log(`[room] created: ${code}`);
  }
  // Cancel any pending cleanup since someone is joining
  if (room.cleanupTimer) {
    clearTimeout(room.cleanupTimer);
    room.cleanupTimer = null;
  }
  return room;
}

function scheduleRoomCleanup(room: RoomState) {
  if (room.cleanupTimer) clearTimeout(room.cleanupTimer);

  // Only schedule if no online clients
  const hasOnline = Array.from(room.clients.values()).some((c) => c.online);
  if (hasOnline) return;

  room.cleanupTimer = setTimeout(() => {
    // Double-check no one reconnected
    const stillHasOnline = Array.from(room.clients.values()).some((c) => c.online);
    if (!stillHasOnline) {
      rooms.delete(room.code);
      console.log(`[room] deleted (TTL expired): ${room.code}`);
    }
  }, ROOM_TTL_MS);
}

// --- Member List ---

function buildMemberList(room: RoomState): MemberInfo[] {
  return Array.from(room.clients.values()).map((c) => ({
    id: c.id,
    name: c.name,
    online: c.online,
    last_seen: c.lastPing,
    location: c.location,
  }));
}

function broadcastMembers(room: RoomState) {
  const members = buildMemberList(room);
  const msg: WireMessage = {
    type: "members",
    id: crypto.randomUUID(),
    sender: "server",
    sender_id: "server",
    room: room.code,
    timestamp: Date.now(),
    payload: { members },
  };
  const data = JSON.stringify(msg);
  for (const client of room.clients.values()) {
    if (client.online) {
      try {
        client.ws.send(data);
      } catch {
        // Client may have disconnected
      }
    }
  }
}

// --- Relay ---

function relayToRoom(
  room: RoomState,
  message: string,
  senderId: string,
  includeSender: boolean
) {
  for (const client of room.clients.values()) {
    if (!client.online) continue;
    if (!includeSender && client.id === senderId) continue;
    try {
      client.ws.send(message);
      totalMessagesRelayed++;
    } catch {
      // Client gone
    }
  }
}

// --- Heartbeat Monitor ---

const heartbeatInterval = setInterval(() => {
  const now = Date.now();
  for (const room of rooms.values()) {
    let changed = false;
    for (const client of room.clients.values()) {
      if (client.online && now - client.lastPing > HEARTBEAT_TIMEOUT_MS) {
        client.online = false;
        changed = true;
        console.log(`[heartbeat] ${client.name} (${client.id}) timed out in room ${room.code}`);
      }
    }
    if (changed) {
      broadcastMembers(room);
      scheduleRoomCleanup(room);
    }
  }
}, 15_000); // Check every 15s

// Prevent the interval from keeping the process alive during shutdown
if (heartbeatInterval.unref) heartbeatInterval.unref();

// --- Public API ---

export function handleJoin(
  ws: ServerWebSocket<ConnectParams>,
  params: ConnectParams
): { error?: string } {
  const { room: roomCode, id, name } = params;

  if (!isValidRoomCode(roomCode)) {
    return { error: "Invalid room code. Must be 3-32 alphanumeric/hyphen characters." };
  }

  const room = getOrCreateRoom(roomCode);

  // Check capacity (excluding reconnects)
  if (!room.clients.has(id) && room.clients.size >= MAX_MEMBERS) {
    return { error: `Room is full (max ${MAX_MEMBERS} members).` };
  }

  // Cancel any pending disconnect grace timer for this device
  const disconnectKey = `${roomCode}:${id}`;
  if (pendingDisconnects.has(disconnectKey)) {
    clearTimeout(pendingDisconnects.get(disconnectKey)!);
    pendingDisconnects.delete(disconnectKey);
    console.log(`[~] ${name} (${id}) reconnected within grace period — no leave broadcast`);
  }

  // Disconnect any existing connection for this device
  const existing = room.clients.get(id);
  if (existing && existing.online) {
    try {
      existing.ws.close(1000, "Replaced by new connection");
    } catch {
      // Already closed
    }
  }

  const client: Client = {
    ws,
    id,
    name,
    room: roomCode,
    joinedAt: Date.now(),
    lastPing: Date.now(),
    online: true,
    location: existing?.location ?? null, // Preserve location on reconnect
    messageTimestamps: [],
  };

  room.clients.set(id, client);
  currentConnections++;
  if (currentConnections > peakConnections) peakConnections = currentConnections;

  // If this was a reconnect within grace period, skip the join broadcast (other clients never saw them leave)
  const isGraceReconnect = existing && !existing.online;
  if (isGraceReconnect) {
    console.log(`[+] ${name} (${id}) silently reconnected to room ${roomCode}`);
  } else {
    console.log(`[+] ${name} (${id}) joined room ${roomCode} | ${room.clients.size} members`);

    // Broadcast join to other members
    const joinMsg: WireMessage = {
      type: "join",
      id: crypto.randomUUID(),
      sender: name,
      sender_id: id,
      room: roomCode,
      timestamp: Date.now(),
      payload: {},
    };
    relayToRoom(room, JSON.stringify(joinMsg), id, false);
  }

  // Send current members list to the joining client
  const membersMsg: WireMessage = {
    type: "members",
    id: crypto.randomUUID(),
    sender: "server",
    sender_id: "server",
    room: roomCode,
    timestamp: Date.now(),
    payload: { members: buildMemberList(room) },
  };
  try {
    ws.send(JSON.stringify(membersMsg));
  } catch {
    // If we can't send, the client will get cleaned up
  }

  // Broadcast updated member list to everyone else
  broadcastMembers(room);

  return {};
}

// Grace period: delay leave broadcast to absorb rapid reconnects (mobile browser throttling)
const DISCONNECT_GRACE_MS = 5000;
const pendingDisconnects = new Map<string, ReturnType<typeof setTimeout>>();

export function handleDisconnect(ws: ServerWebSocket<ConnectParams>) {
  const { room: roomCode, id, name } = ws.data;
  const room = rooms.get(roomCode);
  if (!room) return;

  const client = room.clients.get(id);
  if (!client) return;

  // Only process if this is the current connection (not a stale one)
  if (client.ws !== ws) return;

  client.online = false;
  currentConnections = Math.max(0, currentConnections - 1);

  console.log(
    `[~] ${name} (${id}) disconnected from room ${roomCode} — grace period ${DISCONNECT_GRACE_MS}ms`
  );

  // Delay the leave broadcast — if they reconnect within the grace period, cancel it
  const key = `${roomCode}:${id}`;
  if (pendingDisconnects.has(key)) clearTimeout(pendingDisconnects.get(key)!);

  pendingDisconnects.set(key, setTimeout(() => {
    pendingDisconnects.delete(key);

    // Check if they reconnected during the grace period
    const currentClient = room.clients.get(id);
    if (currentClient && currentClient.online) {
      // They reconnected — no leave broadcast needed
      return;
    }

    // Still offline after grace period — broadcast leave
    if (currentClient) currentClient.location = null; // Clear location (privacy)

    console.log(
      `[-] ${name} (${id}) left room ${roomCode} (after grace) | ${room.clients.size} members`
    );

    const leaveMsg: WireMessage = {
      type: "leave",
      id: crypto.randomUUID(),
      sender: name,
      sender_id: id,
      room: roomCode,
      timestamp: Date.now(),
      payload: {},
    };
    relayToRoom(room, JSON.stringify(leaveMsg), id, false);
    broadcastMembers(room);
    scheduleRoomCleanup(room);
  }, DISCONNECT_GRACE_MS));
}

export function handleMessage(
  ws: ServerWebSocket<ConnectParams>,
  raw: string | Buffer
) {
  const { room: roomCode, id } = ws.data;
  const room = rooms.get(roomCode);
  if (!room) return;

  const client = room.clients.get(id);
  if (!client || !client.online) return;

  // Size check
  const size = typeof raw === "string" ? raw.length : raw.byteLength;
  if (size > MAX_PAYLOAD_BYTES) {
    const errorMsg = JSON.stringify({
      type: "error",
      payload: { message: "Message too large (max 2MB)" },
    });
    try {
      ws.send(errorMsg);
    } catch {}
    return;
  }

  // Rate limit
  if (!checkRateLimit(client)) {
    const errorMsg = JSON.stringify({
      type: "error",
      payload: { message: "Rate limited (max 60 messages/minute)" },
    });
    try {
      ws.send(errorMsg);
    } catch {}
    return;
  }

  // Parse JSON
  let msg: WireMessage;
  try {
    msg = JSON.parse(typeof raw === "string" ? raw : new TextDecoder().decode(raw));
  } catch {
    return; // Invalid JSON, silently drop
  }

  // Ensure sender fields match the authenticated connection
  msg.sender_id = id;
  msg.sender = client.name;
  msg.room = roomCode;

  switch (msg.type) {
    case "ping":
      client.lastPing = Date.now();
      const pong: WireMessage = {
        type: "pong",
        id: msg.id,
        sender: "server",
        sender_id: "server",
        room: roomCode,
        timestamp: Date.now(),
        payload: {},
      };
      try {
        ws.send(JSON.stringify(pong));
      } catch {}
      break;

    case "voice": {
      // Handle TTL for mesh relay support
      const ttl = typeof msg.ttl === "number" ? msg.ttl : 1;
      if (ttl <= 0) return; // Drop expired messages

      const relayMsg = { ...msg, ttl: ttl - 1 };
      relayToRoom(room, JSON.stringify(relayMsg), id, false); // Not back to sender
      break;
    }

    case "location": {
      // Store latest location for this member
      if (msg.payload && typeof msg.payload === "object") {
        client.location = {
          lat: msg.payload.lat as number,
          lng: msg.payload.lng as number,
          accuracy: msg.payload.accuracy as number | undefined,
          altitude: msg.payload.altitude as number | undefined,
          heading: msg.payload.heading as number | undefined,
          speed: msg.payload.speed as number | undefined,
        };
      }
      // Relay to all room members (including sender for confirmation)
      relayToRoom(room, JSON.stringify(msg), id, true);
      break;
    }

    case "transcription": {
      // Relay transcription to all other members
      relayToRoom(room, JSON.stringify(msg), id, false);
      break;
    }

    case "join":
    case "leave":
      // These are server-managed, ignore client-sent versions
      break;

    default:
      // Unknown type, relay anyway for forward compatibility
      relayToRoom(room, JSON.stringify(msg), id, false);
      break;
  }
}

// --- Stats ---

export function getStats() {
  return {
    status: "ok",
    rooms: rooms.size,
    connections: currentConnections,
  };
}

export function getDetailedStats() {
  const startTime = Date.now() - process.uptime() * 1000;
  return {
    uptime_seconds: Math.floor(process.uptime()),
    started_at: new Date(startTime).toISOString(),
    total_messages_relayed: totalMessagesRelayed,
    peak_connections: peakConnections,
    current_connections: currentConnections,
    active_rooms: rooms.size,
  };
}

export function getRoomList() {
  const list: { code: string; members: number; created_at: string }[] = [];
  for (const room of rooms.values()) {
    const onlineCount = Array.from(room.clients.values()).filter((c) => c.online).length;
    list.push({
      code: room.code,
      members: onlineCount,
      created_at: new Date(room.createdAt).toISOString(),
    });
  }
  return list;
}
