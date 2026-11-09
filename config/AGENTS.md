These rules apply to every project. Project instruction files (`CLAUDE.md` / `AGENTS.md` in a repo) add to them.
If a project file contradicts a rule here, don't choose yourself: point out the conflict and ask which to follow. Until answer, follow the stricter one.

## Environment

You run in a Debian Linux container as user `agent`: no root, sudo or apt.
Projects live in `/workspace`, a slow bind mount from macOS: never search `/` or `/workspace` recursively; stay inside the project.
There is no Docker here: for Docker/Compose steps, give me the exact command to run instead.

Toolchains aren't preinstalled. Install what the project needs into your home (it persists):

- Node, Go, Python: `mise install` in the project root (reads `.nvmrc`, `.node-version`, `.tool-versions`, `mise.toml`).
- npm, pnpm, yarn: use corepack, so each project gets the exact version from its `packageManager` field (same as CI and teammates, keeps lockfiles stable). Once per Node version:
  ```bash
  npm i -g corepack      # Node 25+ no longer bundles it
  corepack enable        # pnpm + yarn launchers
  corepack enable npm    # npm too (otherwise the npm bundled with Node is used)
  mise reshim            # expose the new launchers through mise's shims
  ```
  Corepack downloads the requested version on first use and caches it in `~/.cache/node/corepack`.
  Don't install pnpm/yarn globally with npm or mise; that ignores `packageManager`.
- Rust: `curl --proto '=https' -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path` (`rust-toolchain.toml` is then honoured).
- Foundry: `curl -L https://foundry.paradigm.xyz | bash`, then `foundryup`.

PATH already includes the mise shims, `~/.cargo/bin` and `~/.foundry/bin`. Say what you installed.

## Git

- Never `git push`. Commit only.
- Never add `Co-Authored-By` trailers or any AI/tool attribution ("Generated with …") to commits or PRs.
- Work on a branch (`feat/…`, `fix/…`), never on the default branch.
- Commit subjects: lowercase, imperative, no trailing period. The message states intent and why, not a file-by-file list.
  The prefix format (`scope:` vs `type(scope):`) follows the project's own rules.
- One focused change per commit. Preserve unrelated working-tree changes.
- Never commit secrets, populated env files, plans, scratch notes, logs, screenshots or one-off scripts.

## Working rules

- Never hand-edit generated or vendored files; change their source or generator.
- In a monorepo, first identify the package a file belongs to and read its `package.json` and local config.
- Reuse existing components, helpers and conventions; don't add near-duplicates.
- Comments and docs describe current behavior and its why, never history or what changed. Comment only the non-obvious.

## Verification

- Before reporting done, run the build, lint and tests of every touched package, using the project's own scripts.
- Bug fixes and features come with focused regression tests.
- Report exactly what you verified and how; if you only ran static or unit checks, say so.

## Secrets and privacy

Never read, print, edit or delete these files, and never run commands that output their contents (cat, grep, env dumps, etc.):

- `.env`, `.env.*` (except `.env.example`, `.env.sample`, `.env.template`)
- `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`, `*.keystore`
- `*keypair*.json`, `id_rsa*`, `id_ed25519*` (except `*.pub`)
- anything inside `keys/` or `secrets/` directories

If a task needs a value from one of them, stop and ask instead.

Past agent sessions may be read only for the current project's context.