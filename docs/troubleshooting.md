
# Troubleshooting & Migration

This guide covers common issues when migrating existing Claude Code and OpenAI Codex CLI state from macOS into the Docker-based AI Agent Sandbox.

It assumes:

- macOS projects are stored under `~/Workspace`.
- The workspace is mounted inside Docker at `/workspace`.
- Claude state is mounted at `/home/agent/.claude`.
- Codex state is mounted at `/home/agent/.codex`.
- Agent state is stored in the repository's `state/` directory.

Replace `yourusername` with your actual macOS username where necessary.

## 1. Claude Code: Existing project history is missing

Claude Code organizes project history using directory names derived from absolute project paths.

For example, on macOS:

```text
/Users/yourusername/Workspace/my-project
```

The corresponding history directory is:

```text
~/.claude/projects/-Users-yourusername-Workspace-my-project
```

Inside Docker, the same project is located at:

```text
/workspace/my-project
```

Claude therefore expects:

```text
~/.claude/projects/-workspace-my-project
```

The original history still exists, but Claude doesn't find it under the new project path.

### Fix: Create symlinks

Run inside the Docker container:

```bash
cd ~/.claude/projects

for old in -Users-yourusername-Workspace-*; do
    [ -d "$old" ] || continue

    new="-workspace-${old#-Users-yourusername-Workspace-}"

    [ -e "$new" ] || ln -s -- "$old" "$new"
done
```

This creates symlinks from Docker project paths to the original macOS history directories.

Example:

```text
-workspace-my-project
    -> -Users-yourusername-Workspace-my-project
```

No conversations are deleted or duplicated.

Because `~/.claude` is bind-mounted to `./state/claude`, the symlinks persist across container recreation.

### Verify

Open your project inside Docker:

```bash
cd /workspace/my-project
claude
```

Check whether the previous conversations are available.

If not, inspect the actual directory names:

```bash
ls -la ~/.claude/projects
```

The migration script assumes your original projects were stored directly under `~/Workspace`.

---

## 2. Codex: Existing conversations are missing in VS Code

Codex stores conversation history in JSONL session files and maintains a SQLite session index.

After copying Codex state from macOS, sessions may still reference paths such as:

```text
/Users/yourusername/Workspace/my-project
/Users/yourusername/.codex/sessions/...
```

Inside Docker, those paths should be:

```text
/workspace/my-project
/home/agent/.codex/sessions/...
```

This can cause the VS Code Codex extension to show no previous conversations, even though the session files exist.

### Step 1: Verify that history exists

Run inside Docker:

```bash
codex --no-daemon resume --all
```

If your previous conversations appear, the session files are available.

This command opens sessions in the terminal. It does not automatically make them appear in the VS Code sidebar.

### Step 2: Update JSONL session paths

Run inside Docker:

```bash
find /home/agent/.codex/sessions -type f -name '*.jsonl' \
  -exec sed -i 's|/Users/yourusername/Workspace/|/workspace/|g' {} +
```

This updates the old project paths in existing session files.

Verify that no old workspace paths remain:

```bash
grep -rl '/Users/yourusername/Workspace/' /home/agent/.codex/sessions
```

No output means no matching old paths were found.

### Step 3: Update the SQLite session index

Codex may also retain the original paths in its SQLite database.

Because `./state/codex` is bind-mounted, you can edit the database directly from macOS using the built-in `sqlite3` command.

Run on your Mac, from the `ai-sandbox` repository root:

```bash
sqlite3 ./state/codex/state_5.sqlite "
UPDATE threads
SET
  cwd = REPLACE(
    cwd,
    '/Users/yourusername/Workspace/',
    '/workspace/'
  ),
  rollout_path = REPLACE(
    rollout_path,
    '/Users/yourusername/.codex/',
    '/home/agent/.codex/'
  )
WHERE
  cwd LIKE '/Users/yourusername/Workspace/%'
  OR rollout_path LIKE '/Users/yourusername/.codex/%';

SELECT changes();
"
```

The final number indicates how many session records were updated.

The database filename `state_5.sqlite` corresponds to the Codex version used during this migration. Check the actual filename if using another version.

This updates the existing session records in place without deleting conversations.

### Step 4: Reload VS Code

Inside VS Code:

1. Press `Cmd + Shift + P`.
2. Select `Developer: Reload Window`.
3. Open your project inside the Dev Container.
4. Check the Codex sidebar.

Your existing conversations should now be associated with the Docker project paths.

If the history is still missing, inspect the Codex extension logs and the session database before making further changes.

---

## 3. Codex: IPC socket ENOTSUP error

### Symptoms

The Codex VS Code extension logs an error similar to:

```text
listen ENOTSUP: operation not supported on socket
/home/agent/.codex/ipc/ipc.sock
```

### Cause

Codex uses Unix domain sockets for local communication.

On Docker Desktop for macOS, the bind-mounted host filesystem may not support creating these sockets.

The Codex state directory is bind-mounted from macOS:

```yaml
- type: bind
  source: ./state/codex
  target: /home/agent/.codex
```

This preserves history but can interfere with IPC socket creation.

### Fix: Use an in-memory tmpfs for IPC

Keep the existing Codex bind mount and mount a `tmpfs` over its IPC directory:

```yaml
volumes:
  - type: bind
    source: ./state/codex
    target: /home/agent/.codex

tmpfs:
  - /home/agent/.codex/ipc:uid=1000,gid=1000,mode=700
```

`uid=1000,gid=1000` makes the directory belong to the `agent` user. Without it, Codex logs `Codex IPC directory is not owned by the current user` and can't start its IPC router.

Keep the other existing mounts and security settings unchanged.

Recreate the container:

```bash
docker compose up -d --force-recreate
```

### Result

- Codex sessions remain in `./state/codex`.
- Codex configuration remains in `./state/codex`.
- IPC sockets use a native Linux filesystem owned by the agent, recreated empty on every container start.
- Session history persists across container recreation.

The IPC fix and historical session-path migration are separate operations. Both may be necessary.

---

## 4. Persistence and container recreation

The sandbox uses two types of persistent storage.

### Bind mounts

```text
./state/claude      -> /home/agent/.claude
./state/codex       -> /home/agent/.codex
./state/claude.json -> /home/agent/.claude.json
```

These directories and files live directly on your Mac.

Changes made inside Docker are reflected in the corresponding repository files.

They survive:

- Container restarts
- Container recreation
- Image rebuilds

### Named volumes

```text
agent-home -> /home/agent
```

These volumes are managed by Docker and persist independently of the container.

They also survive normal container recreation and image rebuilds.

Unlike bind mounts, their contents do not appear directly in the repository's `state/` directory.

### Safe container recreation

From the repository root:

```bash
docker compose up -d --force-recreate
```

If the Dockerfile has changed:

```bash
docker compose up -d --build
```

Both commands preserve existing named volumes.

**Avoid:**

```bash
docker compose down -v
```

The `-v` option removes Compose-managed named volumes, including the persistent home volume.

### Important distinction

The `agent-home` named volume does not replace the agent-specific bind mounts.

With the configuration above:

- Claude and Codex history remains in `./state/`.
- Other home-directory files persist in `agent-home`.
- Codex IPC uses an in-memory `tmpfs`.

This keeps historical agent state accessible from macOS while allowing Linux-specific IPC functionality inside Docker.

---

## 5. Quick diagnostics

Run these inside the container unless otherwise indicated.

### Check the current user and workspace

```bash
whoami
pwd
```

Expected:

```text
agent
/workspace
```

### Check installed agents

```bash
claude --version
codex --version
```

### Check Claude history

```bash
ls -la ~/.claude/projects
```

### Check Codex sessions

```bash
codex --no-daemon resume --all
```

### Check Codex SQLite files

```bash
ls -lh ~/.codex/*.sqlite
```

### Check active Docker mounts

Run on your Mac:

```bash
docker compose config
```

Review the `volumes` section of the `agent` service.

### Restart the container

Run on your Mac:

```bash
docker compose restart agent
```

### Recreate the container

Run on your Mac:

```bash
docker compose up -d --force-recreate
```

Existing bind-mounted agent data and named volumes remain persistent.
