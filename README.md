# Nanoclaw on RunPod Hub

Autonomous personal AI assistant powered by [Claude](https://anthropic.com/claude). Nanoclaw runs in isolated Docker containers per conversation group, supports WhatsApp and Telegram, and exposes an HTTP/REST API — all configurable via environment variables, no source modifications required.

---

## Quick Start

1. Deploy from [RunPod Hub](https://runpod.io/hub) — search for **Nanoclaw AI Assistant**
2. Set `ANTHROPIC_API_KEY` to your key from [console.anthropic.com](https://console.anthropic.com)
3. Click **Deploy**
4. The pod starts and exposes port `3000`

---

## WhatsApp Setup

WhatsApp requires a one-time QR code scan to link the assistant to your account.

1. After deploy, open `http://<pod-ip>:3000/qr` in your browser
2. Open WhatsApp on your phone → **Linked Devices** → **Link a Device**
3. Scan the QR code displayed in the browser
4. Done — Nanoclaw will now respond to messages in your WhatsApp

> The QR endpoint returns HTTP 202 while Nanoclaw is still initializing. Refresh after a few seconds if you see a "pending" response.

---

## Telegram Setup

1. Open [@BotFather](https://t.me/BotFather) on Telegram and run `/newbot`
2. Copy the token it gives you
3. Set `TELEGRAM_BOT_TOKEN` in your pod's environment variables (redeploy or set before first deploy)
4. Message your new bot — Nanoclaw will respond

---

## HTTP / REST API

Send messages to Nanoclaw programmatically via the HTTP sidecar.

**Endpoint:** `POST http://<pod-ip>:3000/message`

**Request body (JSON):**

| Field   | Type   | Required | Description                                      |
|---------|--------|----------|--------------------------------------------------|
| `text`  | string | yes      | The message text to send                         |
| `group` | string | no       | Conversation group name (default: `"default"`)   |
| `from`  | string | no       | Sender identifier (default: `"http-api"`)        |

**Example:**

```bash
curl -X POST http://<pod-ip>:3000/message \
  -H "Content-Type: application/json" \
  -d '{"text": "What is the weather in Berlin?", "group": "default"}'
```

**Response:**

```json
{ "status": "queued", "file": "msg_1710000000000_abc123.json" }
```

**Health check:**

```bash
curl http://<pod-ip>:3000/health
# {"status":"ok","service":"nanoclaw-runpod"}
```

---

## Environment Variables

| Variable             | Required | Default                                      | Description                                         |
|----------------------|----------|----------------------------------------------|-----------------------------------------------------|
| `ANTHROPIC_API_KEY`  | yes      | —                                            | Anthropic API key for Claude access                 |
| `ASSISTANT_NAME`     | no       | `Andy`                                       | Trigger name used to address the assistant          |
| `TELEGRAM_BOT_TOKEN` | no       | —                                            | Telegram bot token. Leave empty to disable Telegram |
| `TZ`                 | no       | `UTC`                                        | Timezone for scheduled tasks (e.g. `Europe/Berlin`) |
| `CONTAINER_TIMEOUT`  | no       | `1800000`                                    | Agent sub-container timeout in milliseconds         |
| `CONTAINER_IMAGE`    | no       | `ghcr.io/qwibitai/nanoclaw-agent:latest`     | Docker image used for agent sub-containers          |
| `ANTHROPIC_BASE_URL` | no       | —                                            | Override Anthropic API base URL (e.g. for proxies)  |

---

## Architecture

```
RunPod Pod (docker:dind)
├── dockerd              — Docker daemon (needed for Nanoclaw sub-containers)
├── Nanoclaw             — Core assistant process (npm start)
│   ├── WhatsApp channel — via whatsapp-web.js
│   ├── Telegram channel — via skill loaded from /app/skills/telegram.md
│   └── Sub-containers   — one isolated container per conversation group
└── HTTP sidecar (port 3000)
    ├── GET  /health     — liveness check
    ├── GET  /qr         — WhatsApp QR code image
    └── POST /message    — REST API → Nanoclaw IPC
```

---

## Local Build & Test

```bash
# Build
docker build -t nanoclaw-runpod .

# Run (privileged required for Docker-in-Docker)
docker run --privileged -p 3000:3000 \
  -e ANTHROPIC_API_KEY=sk-ant-... \
  -e ASSISTANT_NAME=Andy \
  nanoclaw-runpod

# Check health
curl http://localhost:3000/health

# Check WhatsApp QR
open http://localhost:3000/qr

# Send a test message
curl -X POST http://localhost:3000/message \
  -H "Content-Type: application/json" \
  -d '{"text":"hello","group":"default"}'
```

---

## Publishing to RunPod Hub

See the [RunPod Hub Publishing Guide](https://docs.runpod.io/hub/publishing-guide).

1. Push this repo to GitHub with a release tag
2. Submit via the RunPod Hub publisher portal
3. `.runpod/hub.json` defines the template metadata and env var inputs
4. `.runpod/tests.json` defines the automated health check RunPod runs on deploy

---

## Links

- [Nanoclaw](https://nanoclaws.io) — [Docs](https://nanoclaws.io/docs)
- [RunPod Hub](https://runpod.io/hub)
- [Anthropic Console](https://console.anthropic.com)
