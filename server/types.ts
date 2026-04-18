/**
 * Holler Relay Server — Wire Protocol Types
 *
 * Shared message format between iOS app, Watch app, and relay server.
 * All WebSocket messages are JSON-encoded WireMessage objects.
 */

export type MessageType =
  | "voice"
  | "location"
  | "join"
  | "leave"
  | "ping"
  | "pong"
  | "members"
  | "transcription";

export interface WireMessage {
  type: MessageType;
  id: string;
  sender: string;
  sender_id: string;
  room: string;
  timestamp: number;
  payload: Record<string, unknown>;
  ttl?: number;
}

export interface MemberInfo {
  id: string;
  name: string;
  online: boolean;
  last_seen: number;
  location?: LocationPayload | null;
}

export interface LocationPayload {
  lat: number;
  lng: number;
  accuracy?: number;
  altitude?: number;
  heading?: number;
  speed?: number;
}

export interface VoicePayload {
  audio: string; // base64-encoded audio
  duration_ms?: number;
  format?: string;
  message_id?: string;
}

export interface TranscriptionPayload {
  message_id: string;
  text: string;
  is_final?: boolean;
}

export interface ConnectParams {
  room: string;
  id: string;
  name: string;
}
