# Purge: clean up your Mac after moving to the sandbox

Once agents and builds run inside the container, your Mac no longer needs local agents, language toolchains, or package caches. Removing them:

- makes sure no agent can run outside the container by accident;
- frees disk space (often tens of GB in caches and toolchains).

Do this **last**, after the sandbox has worked for you for a while. Every step is optional; skip anything you still use on the Mac.

## 0. Before you start

Confirm the sandbox covers everything you need:

- [ ] `ai <project>` opens your projects attached to the container.
- [ ] Claude Code and Codex work in the container, and your history shows up (see [troubleshooting.md](troubleshooting.md)).
- [ ] Your projects build and test inside the container (`docker compose exec agent bash`).
- [ ] You have a backup (Time Machine or similar).

See what is taking space:

```bash
du -sh ~/.npm ~/.yarn ~/Library/Caches/Yarn ~/Library/pnpm ~/.pnpm-store \
       ~/.nvm ~/.volta ~/.bun ~/.rustup ~/.cargo ~/.foundry ~/.svm ~/go \
       ~/Library/Caches/go-build ~/.m2 ~/.gradle ~/.local/share/solana \
       ~/.claude ~/.codex ~/.local/share/claude 2>/dev/null | sort -h
```

## 1. Stop agents running on the Mac

Close every VS Code window that is **not** attached to the container. Attached windows show `Container ai-sandbox-agent` (or similar) in the bottom-left corner.

Check that nothing is left:

```bash
ps -axo pid,args | grep -E 'native-binary/claude|bin/macos-aarch64/codex' | grep -v grep
```

No output means no agent is running on the Mac.

## 2. Remove the agent extensions from local VS Code

VS Code keeps local extensions (on the Mac) and container extensions separately. Removing the local copies does not affect the container.

In a **local** window: Extensions view (`Cmd+Shift+X`) → uninstall **Claude Code**, **Codex**, and **Codex Audio** (if installed).

Or from the terminal (this only affects the local install):

```bash
code --uninstall-extension anthropic.claude-code
code --uninstall-extension openai.chatgpt
code --uninstall-extension openai.codex-audio
```

Check:

```bash
ls ~/.vscode/extensions | grep -Ei 'claude|chatgpt|codex' || echo "none left"
```

Keep the **Dev Containers** extension; the sandbox needs it.

## 3. Remove the agent CLIs from the Mac

Remove whichever of these you have.

Claude Code (native installer):

```bash
rm -f ~/.local/bin/claude
rm -rf ~/.local/share/claude ~/.cache/claude
```

Claude Code or Codex installed with npm or Homebrew:

```bash
npm uninstall -g @anthropic-ai/claude-code @openai/codex
brew uninstall codex claude-code 2>/dev/null
```

Check:

```bash
command -v claude codex || echo "none left"
```

## 4. Archive agent state on the Mac

`~/.claude`, `~/.codex` and `~/.claude.json` hold your original sessions, memory and logins. The sandbox uses its own copies in `state/`.

If you kept using agents on the Mac after migrating, those newer sessions exist only here, so archive instead of deleting:

```bash
tar -czf ~/agent-state-mac-$(date +%F).tar.gz -C ~ .claude .codex .claude.json
```

Once you are sure you don't need it:

```bash
rm -rf ~/.claude ~/.codex ~/.claude.json
```

The archive contains login tokens. Keep it somewhere private, and delete it when you no longer need it.

Claude Code on macOS also stores its login in the Keychain. To remove it:

```bash
security delete-generic-password -s "Claude Code-credentials"
```

## 5. Remove language toolchains and package caches

Builds now run in the container, which installs its own toolchains in the `agent-home` volume.

**Before you delete anything:** keep whatever you still use on the Mac outside the sandbox.

Package caches (safe to delete; they are only caches):

```bash
rm -rf ~/.npm ~/Library/Caches/Yarn ~/.yarn/berry/cache ~/Library/pnpm/store ~/.pnpm-store
rm -rf ~/Library/Caches/go-build ~/.m2/repository ~/.gradle/caches
```

These commands delete only the caches. The settings files next to them, such as `~/.m2/settings.xml`, `~/.gradle/gradle.properties`, `~/.npmrc` and `~/.yarnrc`, can hold registry passwords or tokens. Check them before you delete them.

Toolchains:

```bash
rm -rf ~/.nvm ~/.volta ~/.bun              # Node
rm -rf ~/.rustup ~/.cargo                  # Rust
rm -rf ~/.foundry ~/.svm                   # Foundry / Solidity compilers
chmod -R u+w ~/go && rm -rf ~/go           # Go (the module cache is read-only by design)
```

Some toolchain folders also hold keys. For example, Foundry keeps keystores in `~/.foundry/keystores`, and Sui keeps its keystore in `~/.sui`. Back up anything you need before deleting.

### Tools installed outside your home folder

Official installers (`.pkg` files) put tools in system locations rather than in your home folder. These are usually owned by root, so removing them needs `sudo`. Look in:

```bash
ls -l /usr/local/bin             # Node, Go, old CLIs; check where each link points
ls /usr/local                    # whole tool folders (for example git, n, texlive)
ls /Library/Frameworks           # runtimes such as Mono or Python.org Python
ls /etc/paths.d                  # one file per extra PATH entry; remove those of deleted tools
ls /Library/LaunchDaemons ~/Library/LaunchAgents   # background services of removed apps
```

### Homebrew

**Check your login shell first:**

```bash
dscl . -read ~ UserShell
```

If it points into Homebrew (for example `/usr/local/bin/bash` or `/opt/homebrew/bin/zsh`), switch to another shell **before** you uninstall that formula or Homebrew itself. Otherwise Terminal can no longer open a shell:

```bash
chsh -s /bin/zsh
```

Review what's installed, then remove language runtimes you no longer use:

```bash
brew leaves
brew uninstall node go rust python@3.12    # example; pick from your list
brew autoremove && brew cleanup --prune=all
```

`brew uninstall` stops at the first formula it can't remove, for example one that another formula still needs. Read the error, then run it again without that formula.

**Keep the Xcode Command Line Tools** if you use `git` or Homebrew on the Mac. Removing them also removes macOS's `git`.

### Intel Homebrew on Apple Silicon

On an Apple Silicon Mac, check:

```bash
brew --prefix    # /opt/homebrew = native; /usr/local = Intel, runs under Rosetta
uname -m         # in a new terminal: arm64 = native; x86_64 = running under Rosetta
```

A Homebrew in `/usr/local` installs Intel builds. If your login shell comes from it, everything you start from that shell runs under Rosetta, including tools that install themselves, which then pick their Intel version too. To move to a native Homebrew, keep this order:

1. Save the list of what you use: `brew leaves` and `brew list --cask`.
2. Install the native Homebrew. `arch -arm64` makes sure it doesn't install the Intel version again:
   ```bash
   arch -arm64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```
3. Add `eval "$(/opt/homebrew/bin/brew shellenv)"` to your shell config, and reinstall what you still need with `/opt/homebrew/bin/brew install ...`.
4. If your login shell came from the old Homebrew, switch it to the native one:
   ```bash
   echo /opt/homebrew/bin/bash | sudo tee -a /etc/shells && chsh -s /opt/homebrew/bin/bash
   ```
   Quit and reopen Terminal and VS Code, then check that `uname -m` prints `arm64`.
5. Uninstall the old Homebrew:
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" -- --path=/usr/local
   ```
   Casks with their own uninstallers (for example VirtualBox) need your password, so uninstall them first in a terminal.

The first install downloads Homebrew's full history and shows no progress for a few minutes. It isn't stuck.

## 6. Clean up your shell config

Remove the lines that loaded the toolchains you just deleted. Check every startup file you have: `~/.zshrc`, `~/.zshenv`, `~/.zprofile`, `~/.bash_profile`, `~/.bashrc` and `~/.profile`. Toolchain installers often add the same line to several of them. Look for:

- `nvm` (`NVM_DIR`, `nvm.sh`)
- `. "$HOME/.cargo/env"`
- `~/.foundry/bin`, `~/go/bin`, `GOPATH`,
- `bun`, `pnpm`
- paths that point into a Homebrew you removed (for example `/usr/local/etc/...` completion scripts)
- `~/.local/bin`, if it was only there for Claude

Back up the files first. Afterwards, open a new terminal and check that it starts without errors.

### VS Code's terminal

VS Code's built-in terminal doesn't use the login shell you set with `chsh`. Its default profile runs the first `bash` or `zsh` it finds, often the old macOS `/bin/bash` 3.2. If its terminal shows errors that Terminal doesn't (for example `__git_ps1: command not found`), set the shell explicitly in your VS Code **User** settings:

```json
"terminal.integrated.profiles.osx": {
  "bash": { "path": "/opt/homebrew/bin/bash", "args": ["-l"] }
},
"terminal.integrated.defaultProfile.osx": "bash"
```

Then close the existing terminal tabs. Tabs that are already open keep their old shell.

Keep the sandbox line:

```bash
export PATH="$HOME/Agents/ai-sandbox/bin:$PATH"
```

Open a new terminal afterwards.

## 7. Remove Mac-built dependencies from your projects

`node_modules`, Rust `target/` folders and similar were built for macOS. The container needs Linux builds, so delete them and let the container rebuild.

List first (replace the path with your `PROJECT_DIR`):

```bash
find ~/Workspace -name node_modules -type d -prune
find ~/Workspace -name target -type d -prune -exec test -f {}/../Cargo.toml \; -print
```

Then delete:

```bash
find ~/Workspace -name node_modules -type d -prune -exec rm -rf {} +
find ~/Workspace -name target -type d -prune -exec test -f {}/../Cargo.toml \; -exec rm -rf {} +
```

Reinstall inside the container, per project (for example `npm ci` or `cargo build`).

## 8. Secrets

Agents can read and change everything in the folders mounted into the container, and in the container's home folder. Instructions such as "don't read `.env` files" in `config/AGENTS.md` are rules the agents follow, not something the container enforces.

- [ ] Move `.env` files, private keys and keypairs out of the mounted folders.
- [ ] Rotate any credentials that were inside them while agents had access.
- [ ] Keep high-value keys out of the container entirely, for example deployment keys, program upgrade authorities and wallets. Use separate dev or testnet keys inside the sandbox.

Old credential files in your Mac home folder often outlive the tools that created them. Examples are `~/.git-credentials`, `~/.kube`, `~/.azure`, VPN profiles and old SSH key folders. Revoke the credentials at the provider, then delete the files.

## 9. Final check

```bash
ls ~/.vscode/extensions | grep -Ei 'claude|chatgpt|codex' || echo "no local agent extensions"
command -v claude codex || echo "no agent CLIs on the Mac"
ps -axo args | grep -E 'native-binary/claude|macos-aarch64/codex' | grep -v grep || echo "no agents running on the Mac"
```

Then open a project with `ai <project>` and confirm Claude Code and Codex still work in the container.

If free disk space hasn't gone up, Time Machine local snapshots still hold the deleted files. macOS frees them within about 24 hours. To free them now:

```bash
tmutil thinlocalsnapshots / 999999999999 4
```
