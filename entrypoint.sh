#!/bin/bash
set -e

# ── 1. Start Docker daemon ────────────────────────────────────────────────────
dockerd &
DOCKERD_PID=$!

echo "Waiting for Docker daemon..."
for i in $(seq 1 30); do
  docker info >/dev/null 2>&1 && break
  sleep 1
done
docker info >/dev/null 2>&1 || { echo "ERROR: Docker daemon failed to start"; exit 1; }
echo "Docker daemon ready."

# ── 2. Write /app/.env from environment variables ────────────────────────────
cat > /app/.env <<EOF
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
ASSISTANT_NAME=${ASSISTANT_NAME:-Andy}
CONTAINER_IMAGE=${CONTAINER_IMAGE:-ghcr.io/qwibitai/nanoclaw-agent:latest}
CONTAINER_TIMEOUT=${CONTAINER_TIMEOUT:-1800000}
TZ=${TZ:-UTC}
${ANTHROPIC_BASE_URL:+ANTHROPIC_BASE_URL=${ANTHROPIC_BASE_URL}}
EOF
echo ".env written."

# ── 3. Write Telegram skill if token is set ──────────────────────────────────
mkdir -p /app/skills
if [ -n "${TELEGRAM_BOT_TOKEN}" ]; then
  cat > /app/skills/telegram.md <<EOF
---
name: telegram
description: Telegram channel integration
---

# Telegram Channel

This assistant is connected to a Telegram bot.

Bot token: ${TELEGRAM_BOT_TOKEN}

Respond to messages received via Telegram using the same assistant personality and capabilities.
EOF
  echo "Telegram skill written."
fi

# ── 4. Start HTTP sidecar ────────────────────────────────────────────────────
node - <<'SIDECAR_EOF' &
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 3000;
const QR_PATHS = [
  '/app/.wwebjs_auth/session/qr.png',
  '/app/auth/qr.png',
  '/app/.auth/qr.png',
];
const IPC_DIR = '/app/ipc';

// Ensure IPC directory exists for HTTP→Nanoclaw message passing
fs.mkdirSync(IPC_DIR, { recursive: true });

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  // ── GET /health ──────────────────────────────────────────────────────────
  if (req.method === 'GET' && url.pathname === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', service: 'nanoclaw-runpod' }));
    return;
  }

  // ── GET /qr ──────────────────────────────────────────────────────────────
  if (req.method === 'GET' && url.pathname === '/qr') {
    // Try known QR file locations
    const qrFile = QR_PATHS.find(p => fs.existsSync(p));
    if (qrFile) {
      res.writeHead(200, { 'Content-Type': 'image/png' });
      fs.createReadStream(qrFile).pipe(res);
      return;
    }

    // Try reading QR from Nanoclaw logs
    const logFile = '/app/logs/nanoclaw.log';
    if (fs.existsSync(logFile)) {
      const logs = fs.readFileSync(logFile, 'utf8');
      const qrMatch = logs.match(/QR_CODE_BASE64:([A-Za-z0-9+/=]+)/);
      if (qrMatch) {
        const buf = Buffer.from(qrMatch[1], 'base64');
        res.writeHead(200, { 'Content-Type': 'image/png' });
        res.end(buf);
        return;
      }
    }

    res.writeHead(202, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'pending',
      message: 'WhatsApp QR not yet available. Nanoclaw may still be initializing — retry in a few seconds.'
    }));
    return;
  }

  // ── POST /message ────────────────────────────────────────────────────────
  if (req.method === 'POST' && url.pathname === '/message') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      let payload;
      try {
        payload = JSON.parse(body);
      } catch {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Invalid JSON' }));
        return;
      }

      const { text, group = 'default', from = 'http-api' } = payload;
      if (!text) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: '"text" field is required' }));
        return;
      }

      // Write message as a JSON file into the IPC directory.
      // Nanoclaw's skill/hook mechanism can watch this directory and ingest messages.
      const msgFile = path.join(IPC_DIR, `msg_${Date.now()}_${Math.random().toString(36).slice(2)}.json`);
      const msg = { text, group, from, timestamp: new Date().toISOString() };
      fs.writeFileSync(msgFile, JSON.stringify(msg));

      res.writeHead(202, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'queued', file: path.basename(msgFile) }));
    });
    return;
  }

  // ── 404 ──────────────────────────────────────────────────────────────────
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not found' }));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[sidecar] HTTP server listening on :${PORT}`);
});
SIDECAR_EOF

SIDECAR_PID=$!
echo "HTTP sidecar started (PID ${SIDECAR_PID})."

# ── 5. Start Nanoclaw ────────────────────────────────────────────────────────
echo "Starting Nanoclaw..."
cd /app
exec npm start
