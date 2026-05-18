#
# Multi-stage Dockerfile for Pentest Agent (DeepSeek Edition)
# Debian-based with Chinese mirror optimization
#

# Builder stage - Install tools and dependencies
FROM docker.m.daocloud.io/library/node:22-slim AS builder

# Use Alibaba Cloud mirror for apt (faster in China)
RUN sed -i 's|http://deb.debian.org|http://mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core build tools
    build-essential \
    git \
    curl \
    wget \
    ca-certificates \
    python3 \
    bash \
    && rm -rf /var/lib/apt/lists/*

# Install pnpm
RUN npm install -g pnpm@10.33.0

# Build Node.js application in builder
WORKDIR /app

# Copy workspace manifests for install layer caching
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml .npmrc ./
COPY apps/worker/package.json ./apps/worker/
COPY apps/cli/package.json ./apps/cli/

RUN pnpm install --frozen-lockfile

COPY . .

# Build worker. CLI not needed in Docker
RUN pnpm --filter @shannon/worker run build

# Production-only deps
RUN rm -rf node_modules apps/*/node_modules && pnpm install --frozen-lockfile --prod

# Runtime stage - Minimal production image
FROM docker.m.daocloud.io/library/node:22-slim AS runtime

# Use Alibaba Cloud mirror for apt (faster in China)
RUN sed -i 's|http://deb.debian.org|http://mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources

# Install only runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core utilities
    git \
    bash \
    curl \
    ca-certificates \
    # Chromium browser for Playwright
    chromium \
    # Additional libraries Chromium needs
    libnss3 \
    libfreetype6 \
    libharfbuzz0b \
    # X11 libraries for headless browser
    libx11-6 \
    libxcomposite1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    # Font rendering
    fontconfig \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -g 1001 pentest && \
    useradd -u 1001 -g pentest -s /bin/bash -m pentest

# System-level git config (survives UID remapping in entrypoint)
RUN git config --system user.email "agent@localhost" && \
    git config --system user.name "Pentest Agent" && \
    git config --system --add safe.directory '*'

# Set working directory
WORKDIR /app

# Copy only what the worker needs
COPY --from=builder /app/package.json /app/pnpm-workspace.yaml /app/pnpm-lock.yaml /app/.npmrc /app/
COPY --from=builder /app/node_modules /app/node_modules
COPY --from=builder /app/apps/worker /app/apps/worker
COPY --from=builder /app/apps/cli/package.json /app/apps/cli/package.json

# Install Claude Code + Playwright CLI
# Skip Playwright browser download — use system chromium from apt
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
RUN npm install -g @anthropic-ai/claude-code@2.1.84 @playwright/cli@0.1.1

# Install Playwright MCP skills only (timeout kills browser download, skills install in ~0.5s)
RUN mkdir -p /tmp/.claude/skills/playwright-cli && \
    PW_SKILLS=$(npm root -g)/@playwright/cli/skills && \
    if [ -d "$PW_SKILLS" ]; then \
      cp -r "$PW_SKILLS"/* /tmp/.claude/skills/playwright-cli/; \
    else \
      timeout 10 playwright-cli install --skills || true; \
      cp -r .claude/skills/playwright-cli/ /tmp/.claude/skills/playwright-cli/; \
      rm -rf .claude; \
    fi

# Symlink CLI tools onto PATH
RUN ln -s /app/apps/worker/dist/scripts/save-deliverable.js /usr/local/bin/save-deliverable && \
    chmod +x /app/apps/worker/dist/scripts/save-deliverable.js && \
    ln -s /app/apps/worker/dist/scripts/generate-totp.js /usr/local/bin/generate-totp && \
    chmod +x /app/apps/worker/dist/scripts/generate-totp.js

# Create directories for session data and ensure proper permissions
RUN mkdir -p /app/sessions /app/repos /app/workspaces && \
    mkdir -p /tmp/.cache /tmp/.config /tmp/.npm && \
    chmod 777 /app && \
    chmod 777 /tmp/.cache && \
    chmod 777 /tmp/.config && \
    chmod 777 /tmp/.npm && \
    chown -R pentest:pentest /app /tmp/.claude

COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Set environment variables
ENV NODE_ENV=production
ENV PATH="/usr/local/bin:$PATH"
ENV SHANNON_DOCKER=true
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
ENV PLAYWRIGHT_MCP_EXECUTABLE_PATH=/usr/bin/chromium
ENV npm_config_cache=/tmp/.npm
ENV HOME=/tmp
ENV XDG_CACHE_HOME=/tmp/.cache
ENV XDG_CONFIG_HOME=/tmp/.config

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["node", "apps/worker/dist/temporal/worker.js"]
