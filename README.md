
# AI Agent Sandbox

A Docker-based development environment for running **Claude Code** and **OpenAI Codex CLI** in an isolated Linux container, without giving the agents direct access to your macOS shell or unrestricted access to your filesystem.

Supports VS Code Dev Containers, persistent agent sessions, shared project workspaces, and native CLI installations without requiring Node.js as the container's base image.

## Features

- **Isolated execution** — Agent commands execute inside Docker, not in the host macOS shell.
- **Multiple agents** — Claude Code and OpenAI Codex CLI in one container.
- **Shared workspace** — Read/write access to selected folders of your workspace directory.
- **Persistent history** — Retain sessions, context, memory, skills, and configuration across container restarts and recreation.
- **VS Code integration** — Develop through VS Code using Dev Containers.
- **Reduced privileges** — Non-root user, dropped Linux capabilities, and privilege escalation restrictions.
- **Resource limits** — Configurable CPU, memory, and process limits.
- **Native installations** — No npm installation required for the agents.

## Requirements

- Docker Desktop (macOS) or Docker Engine
- Docker Compose v2
- VS Code with the Dev Containers extension (optional)
- Claude Code and/or Codex access for authentication

## Repository structure

```text
ai-sandbox/
├── Dockerfile
├── compose.yaml
├── .env
├── .gitignore
├── README.md
├── .devcontainer/
│   └── devcontainer.json
├── bin/
│   └── code-ai
├── config/
│   └── AGENTS.md
├── docs/
│   ├── commands.md
│   ├── troubleshooting.md
│   └── purge.md
└── state/
    ├── claude/
    ├── codex/
    └── claude.json
```

The `state/` directory contains private agent state and must not be committed to Git.

`config/AGENTS.md` holds the instructions shared by both agents (environment, toolchains, secrets). It is committed, and mounted read-only as `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`, so agents can't change their own rules.

## Quick start

### 1. Configure your workspace

Create `.env` in the repository root:

```dotenv
PROJECT_DIR=/Users/yourusername/Workspace
```

Set `PROJECT_DIR` to the absolute path of the directory containing your projects.

Agents only see the folders of `PROJECT_DIR` that `compose.yaml` mounts, each at the same path under `/workspace` (for example `PROJECT_DIR/gc` → `/workspace/gc`), with read/write permissions. Everything else in `PROJECT_DIR` stays hidden. To expose another folder, add a mount and recreate the container:

```yaml
- type: bind
  source: ${PROJECT_DIR}/my-folder
  target: /workspace/my-folder
```

### 2. Optional: Migrate existing agent state

If you already use Claude Code or Codex on your Mac, you can preserve your existing sessions, memory, skills, and configuration.

From the repository root, on your Mac:

```bash
mkdir -p state/claude state/codex

rsync -a ~/.claude/ state/claude/
rsync -a ~/.codex/ state/codex/

if [ -f ~/.claude.json ]; then
    cp ~/.claude.json state/claude.json
else
    touch state/claude.json
fi
```

If you don't have existing agent data, create the empty directories and `state/claude.json` file instead.

**Important:** These are independent copies. Changes made inside Docker won't automatically synchronize with the original macOS directories.

Your own `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` are hidden in the container by `config/AGENTS.md`. Merge anything you want to keep into `config/AGENTS.md`.

Historical sessions may not appear automatically because their original macOS project paths differ from the paths inside Docker.

After starting the container, follow [Troubleshooting & Migration](docs/troubleshooting.md) to restore Claude Code and Codex project history.

Authentication may also need to be repeated.

### 3. Configure persistent storage

The Compose service should mount the selected workspace folders, a persistent home directory, and the agent-specific state:

```yaml
volumes:
  - type: bind
    source: ${PROJECT_DIR}/gc
    target: /workspace/gc
  # ...one block per exposed folder

  - type: bind
    source: ./state/claude
    target: /home/agent/.claude

  - type: bind
    source: ./state/codex
    target: /home/agent/.codex

  - type: bind
    source: ./state/claude.json
    target: /home/agent/.claude.json

  - agent-home:/home/agent

tmpfs:
  - /home/agent/.codex/ipc:uid=1000,gid=1000,mode=700
```

The `tmpfs` mount for Codex IPC is important on Docker Desktop for macOS. Codex creates Unix domain sockets there, which the bind-mounted `state/codex` can't hold. It lives in memory, belongs to the `agent` user, and starts empty on every container start.

The top-level Compose configuration must also declare:

```yaml
volumes:
  agent-home:
```

This provides persistent storage for both agent-specific data and other files under `/home/agent`.

Keep the sandbox repository outside the workspace mounted at `/workspace` to avoid exposing private agent state through the workspace mount.

### 4. Build and start

```bash
docker compose up -d --build
```

Check container status:

```bash
docker compose ps
```

### 5. Enter the container

```bash
docker compose exec agent bash
```

Verify the execution environment:

```bash
whoami
pwd
uname -s
```

Expected results:

```text
agent
/workspace
Linux
```

### 6. Launch an agent

Check installed versions:

```bash
codex --version
claude --version
```

Launch Codex:

```bash
cd /workspace/my-project
codex
```

Or Claude Code:

```bash
cd /workspace/my-project
claude
```

Complete authentication if prompted.

## VS Code integration

Install Microsoft's **Dev Containers** extension.

1. Open the `ai-sandbox` repository in VS Code.
2. Start the container with `docker compose up -d`.
3. Open the Command Palette (`Cmd + Shift + P`).
4. Select **Dev Containers: Attach to Running Container**.
5. Select the running `agent` container.
6. Open `/workspace` or an individual project directory inside the container.

Install the following extensions **inside the Dev Container**:

- **Codex** (`openai.chatgpt`)
- **Claude Code** (`anthropic.claude-code`)

Extensions installed locally on macOS are separate from extensions installed in the Dev Container.

Agent commands and extension backends execute inside the container.

### Opening projects with `code-ai`

The `bin/code-ai` script opens a project in a new VS Code window, already attached to the container.

Add this to `~/.zshrc`, then open a new terminal:

```bash
export PATH="$HOME/Agents/ai-sandbox/bin:$PATH"
```

Usage:

```bash
code-ai                 # lists projects
code-ai your-project    # opens that project in a new window, attached to the container
```

### Recommended VS Code settings

In VS Code **User** settings (on the Mac, not Remote):

```json
"chat.disableAIFeatures": true,
"dev.containers.gitCredentialHelperConfigLocation": "none"
```

- `chat.disableAIFeatures`: VS Code starts its own Copilot runtime inside the container even if you don't use Copilot (~24 threads, ~230 MB). Claude Code and Codex are separate extensions and are not affected.
- `dev.containers.gitCredentialHelperConfigLocation`: stops VS Code from forwarding your Mac's Git credentials into the container, so agents can commit but can't push over HTTPS. Push from your Mac instead.

If you attached before setting this, remove the old helper once (run from the `ai-sandbox` folder):

```bash
docker compose exec agent git config --global --unset credential.helper
```

### Project history

When migrating existing agent state from macOS, previous conversations may not immediately appear in the VS Code extensions.

This is caused by differences between macOS project paths and Docker project paths.

For example:

```text
macOS:  /Users/yourusername/Workspace/my-project
Docker: /workspace/my-project
```

Claude Code and Codex handle project history differently.

Follow [Troubleshooting & Migration](docs/troubleshooting.md) for the exact migration steps.

## Persistent storage

The sandbox uses bind mounts and Docker named volumes.

### Bind-mounted agent state

```text
./state/claude      -> /home/agent/.claude
./state/codex       -> /home/agent/.codex
./state/claude.json -> /home/agent/.claude.json
./config/AGENTS.md -> /home/agent/.claude/CLAUDE.md  (read-only)
./config/AGENTS.md -> /home/agent/.codex/AGENTS.md   (read-only)
```

Agent histories, configurations, memory, and skills are stored directly in the repository's `state/` directory on your Mac.

Changes made inside Docker are persisted to these directories.

### Docker named volumes

```text
agent-home -> /home/agent
```

The `agent-home` volume preserves other files in the agent's home directory.

Codex IPC sockets use an in-memory `tmpfs` at `/home/agent/.codex/ipc` instead of a volume, since they only exist while Codex runs.

Named volumes survive normal container restarts, recreation, and image rebuilds.

### Container recreation

Recreate the container without rebuilding the image:

```bash
docker compose up -d --force-recreate
```

Rebuild after modifying the Dockerfile:

```bash
docker compose up -d --build
```

Both preserve existing named volumes.

**Do not use `docker compose down -v` unless you intentionally want to delete the named volumes.**

## Security model

The sandbox reduces the host access available to AI agents.

Recommended container restrictions include:

```yaml
user: agent
privileged: false
cap_drop:
  - ALL
security_opt:
  - no-new-privileges:true
mem_limit: 8g
cpus: 4
pids_limit: 4096
```

The container runs as a non-root user with reduced Linux privileges.

Agents have read/write access to the mounted workspace and persistent agent directories.

They do not automatically receive access to the host macOS shell or files outside the configured mounts.

**Important:** This is not a complete security boundary against every possible threat. Docker daemon access, additional mounts, credentials, network permissions, and container configuration can affect isolation.

Only mount directories you intend to expose to agents.

### Deployment isolation

The deployment container runs independently of the AI development container, with separate processes and environment variables.

Both containers share project directories and installed tooling, but AI agents do not automatically have access to deployment processes or credentials.

Deployment shell history is disabled (`HISTFILE=/dev/null`, `HISTSIZE=0`) to prevent private keys entered in commands from being persisted to the shared home directory.

This isolation assumes neither container has Docker daemon access or elevated host privileges.

**Important:** Because project files and tooling are shared, agents can modify code executed during deployment. Review changes before deploying.

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for:

- Migrating Claude Code project history using symlinks.
- Migrating Codex history from macOS paths to Docker paths.
- Restoring Codex conversations in the VS Code sidebar.
- Fixing Codex Unix socket `ENOTSUP` errors.
- Understanding bind mounts and named-volume persistence.
- Diagnosing missing sessions after container recreation.

## Useful commands

See [docs/commands.md](docs/commands.md) for starting, stopping, rebuilding and inspecting the container.

## Cleaning up

Once everything runs in the sandbox, you can remove local agents, toolchains and caches from your Mac. See [docs/purge.md](docs/purge.md).