
# Agent CLI versions. To upgrade: change the version and rebuild.
# Each tool is downloaded in its own stage, so only the changed one is fetched again.
ARG CODEX_VERSION=0.167.0
ARG CLAUDE_VERSION=2.1.318
ARG MISE_VERSION=2026.10.19

# ---------------------------------------------------------
# Download stages: cached independently and run in parallel
# ---------------------------------------------------------
FROM debian:trixie-slim AS fetch
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl jq zstd \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /out

# Codex CLI
FROM fetch AS codex
ARG CODEX_VERSION
RUN curl -fsSL --retry 5 --retry-all-errors -o codex.tar.gz \
       "https://github.com/openai/codex/releases/download/rust-v${CODEX_VERSION}/codex-aarch64-unknown-linux-musl.tar.gz" \
    && tar -xzf codex.tar.gz --no-same-owner \
    && mv codex-aarch64-unknown-linux-musl codex \
    && rm codex.tar.gz

# Claude Code: compressed download (~3x smaller)
FROM fetch AS claude
ARG CLAUDE_VERSION
RUN base="https://downloads.claude.ai/claude-code-releases/${CLAUDE_VERSION}" \
    && curl -fsSL --retry 5 --retry-all-errors -o manifest.json "$base/manifest.json" \
    && curl -fsSL --retry 5 --retry-all-errors -o manifest.zst.json "$base/manifest.zst.json" \
    && curl -fsSL --retry 5 --retry-all-errors -o claude.zst "$base/linux-arm64/claude.zst" \
    && echo "$(jq -r '.platforms["linux-arm64"].checksum' manifest.zst.json)  claude.zst" | sha256sum -c - \
    && zstd -d -q -c claude.zst | head -c "$(jq -r '.platforms["linux-arm64"].size' manifest.json)" > claude \
    && echo "$(jq -r '.platforms["linux-arm64"].checksum' manifest.json)  claude" | sha256sum -c - \
    && rm claude.zst manifest.json manifest.zst.json

# Mise (Node, Go, Python versions per project)
FROM fetch AS mise
ARG MISE_VERSION
RUN f="mise-v${MISE_VERSION}-linux-arm64" \
    && curl -fsSL --retry 5 --retry-all-errors -O "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/$f" \
    && curl -fsSL --retry 5 --retry-all-errors "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/SHASUMS256.txt" \
       | grep " ./$f\$" | sed 's| \./| |' | sha256sum -c - \
    && mv "$f" mise

# ---------------------------------------------------------
# Sandbox image
# ---------------------------------------------------------
FROM debian:trixie-slim

ENV LANG=C.UTF-8

# System packages (need root, so they live in the image).
# Language toolchains (Node via mise, Rust via rustup, Foundry, Go) are installed
# on demand into the agent's home volume instead.
RUN apt-get update && apt-get install -y --no-install-recommends \
    # CLI basics
    bash ca-certificates curl git git-lfs ripgrep fd-find jq \
    procps less file tree unzip zip xz-utils \
    # Native build deps (Rust linking, node-gyp, Substrate)
    build-essential pkg-config libssl-dev libudev-dev clang libclang-dev cmake protobuf-compiler \
    python3 python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd

# Agent CLIs: root-owned in /usr/local/bin, so they can't update themselves
COPY --from=codex  --chmod=755 /out/codex  /usr/local/bin/codex
COPY --from=claude --chmod=755 /out/claude /usr/local/bin/claude
COPY --from=mise   --chmod=755 /out/mise   /usr/local/bin/mise

ENV DISABLE_AUTOUPDATER=1
# Let mise read .nvmrc / .node-version
ENV MISE_IDIOMATIC_VERSION_FILE_ENABLE_TOOLS=node

RUN useradd -m -s /bin/bash agent
USER agent

ENV HOME=/home/agent

# Colorful Bash prompt
RUN printf '%s\n' \
    'export PS1="\[\033[33;1m\]\u@\h\[\033[32m\]:\w\[\033[0m\]\$ "' \
    'export CLICOLOR=1' \
    'export LS_COLORS=ExFxBxDxCxegedabagacad' \
    >> /home/agent/.bashrc

# Toolchains the agent installs into its home volume
ENV PATH="/home/agent/.foundry/bin:${PATH}"
ENV PATH="/home/agent/.cargo/bin:${PATH}"
ENV PATH="/home/agent/.local/share/mise/shims:${PATH}"

WORKDIR /workspace

CMD ["sleep", "infinity"]
