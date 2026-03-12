FROM docker:dind

# Install Node.js 20, npm, git, curl
RUN apk add --no-cache \
    nodejs \
    npm \
    git \
    curl \
    bash \
    tzdata

# Install Claude CLI globally
RUN npm install -g @anthropic-ai/claude-code

# Clone and build Nanoclaw
RUN git clone https://github.com/qwibitai/nanoclaw /app
WORKDIR /app
RUN npm install && npm run build

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# HTTP sidecar port (REST API + WhatsApp QR display)
EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]
