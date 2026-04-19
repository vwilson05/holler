# Holler At Me

**Push-to-talk for your people.** No accounts. No data stored. Just a shared passphrase and you're in.

[holleratme.app](https://holleratme.app) | [Try the Web App](https://holleratme.app/web)

---

## What is it?

Holler At Me is a privacy-first walkie-talkie for families, friend groups, road trips, and nights out. Hold a button, talk, everyone in your group hears you instantly.

- **Zero auth** — your passphrase is your room key, SHA-256 hashed client-side. No email, no phone number, no account.
- **Works everywhere** — iOS app, web browser (any phone/laptop), Apple Watch. Same room, any device.
- **Privacy-first** — no message storage, no logs. Voice is relayed and forgotten. Rooms auto-delete when empty.
- **Open source** — see exactly what runs. Nothing hidden.

## How it works

1. **Pick a passphrase** — share it with your group (e.g. "timber falcon october sunrise")
2. **Join the room** — open the app or website, enter the phrase
3. **Hold and talk** — press the button, say your thing, release. Everyone hears you.

## Features

- Push-to-talk with slide-to-cancel
- Auto-play incoming messages (hands-free)
- Voice transcription (on-device)
- Live location sharing on a map
- Context-aware channels (home, road trip, event, hangout)
- Haptic identity — know who's talking by vibration pattern
- Background audio — hear messages with the app minimized
- Invite links with pre-filled passphrase
- Apple Watch companion

## Architecture

```
walkie-talkie/
├── WalkieTalkie/          # iOS app (SwiftUI, iOS 17+)
│   ├── Models/            # Channel, VoiceMessage, Member, WireMessage
│   ├── Managers/          # Audio, WebSocket, Multipeer, Location, Transcription, Haptic
│   ├── Views/             # TalkView, ChannelList, Map, Settings, PTT button
│   └── Extensions/        # Theme colors
├── HollerWatch/           # Apple Watch companion (WatchOS 10+)
├── server/                # Relay server (Bun + WebSocket)
│   ├── index.ts           # HTTP routes + WebSocket upgrade
│   ├── room.ts            # Room management, presence, relay
│   └── types.ts           # Wire protocol types
└── web/                   # Web MVP (single HTML file, zero dependencies)
    └── index.html         # Full PTT web app
```

## Wire Protocol

All communication uses JSON over WebSocket:

```json
{
  "type": "voice|location|join|leave|ping|pong|members",
  "id": "<uuid>",
  "sender": "<display_name>",
  "sender_id": "<device_uuid>",
  "room": "<sha256_hash_of_passphrase>",
  "timestamp": 1234567890,
  "payload": { }
}
```

The room code is the first 32 hex characters of `SHA-256(groupName:passphrase)`. The server never sees the original passphrase.

## Run locally

**Relay server:**
```bash
cd server
bun install
bun run index.ts
```

**Web app:**
Open `http://localhost:3000` (served by the relay server)

**iOS app:**
```bash
open WalkieTalkie.xcodeproj
# Set signing team, build to device
```

## Deploy

**Server + Web** (Railway):
```bash
railway up
```

Dockerfile included. The server serves the web client at `/` and handles WebSocket connections at `/ws`.

## Privacy

- Passphrase hashed with SHA-256 before leaving your device
- No accounts, no emails, no phone numbers collected
- No message storage — voice data relayed in real-time and discarded
- No analytics, no tracking
- Rooms auto-delete 1 hour after last disconnect
- Location data held in memory only, cleared on disconnect
- Open source — verify everything

## Tech

- **iOS**: SwiftUI, AVAudioRecorder, Multipeer Connectivity, URLSessionWebSocketTask, CoreLocation, Speech framework, CryptoKit
- **Watch**: SwiftUI, WatchConnectivity, WKExtendedRuntimeSession
- **Web**: Vanilla HTML/CSS/JS, MediaRecorder API, Web Audio API, Web Speech API, WebSocket
- **Server**: Bun, Hono, native WebSocket

## License

MIT

---

Made in San Diego. [holleratme.app](https://holleratme.app)
