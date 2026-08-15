# opencode Setup Transfer

*[한국어 문서](README.md)*

Pack your opencode setup into a single file on one computer, and unpack it automatically on another.

Got a new laptop? Work across a home and an office machine? You don't have to rebuild the skills and settings you've collected.

```
[old machine]  export.sh  →  opencode-setup-personal-….tar.gz  →  [new machine]  import.sh
```

---

## Install

One line, on both machines.

```bash
curl -fsSL https://raw.githubusercontent.com/Gospel-Lab/opencode-setup-transfer/main/install.sh | bash
```

It installs to `~/.config/opencode/skills/opencode-setup-transfer/`.

On the new machine you can skip the install — the archive carries the tool with it, so `import.sh` is already there when you unpack.

## Usage

### 1. Export on the old machine

```bash
~/.config/opencode/skills/opencode-setup-transfer/scripts/export.sh
```

You get `opencode-setup-personal-<date>.tar.gz` on your Desktop. It's usually 1–5 MB, small enough to email yourself.

### 2. Import on the new machine

Move the file to the new machine's Downloads folder, then:

```bash
cd ~/Downloads
tar -xzf opencode-setup-personal-*.tar.gz
cd opencode-setup && ./import.sh
```

**It applies everything without asking.** Existing files are backed up first, then overwritten. Use `./import.sh --ask` if you want to confirm each category.

### 3. Reconnect your services

A wizard walks you through one service at a time.

```bash
~/.config/opencode/skills/opencode-setup-transfer/scripts/connect.sh wizard
```

Supports **GitHub, Firebase, Vercel, Supabase, and Netlify**. For each service it:

1. Installs the CLI if missing (shows the command for your OS, installs on your confirmation)
2. Opens the signup page in your browser if you don't have an account
3. Shows you what the login screen looks like and what to click
4. Verifies the connection actually worked, and explains why if it didn't
5. Skips services already connected, and any you say you don't use

For a quick status check:

```bash
connect.sh check
```

```
Service status

  GitHub     connected  my-github-id
  Firebase   connected  me@example.com
  Vercel     login needed   vercel login
  Supabase   not installed  brew install supabase/tap/supabase
  Netlify    connected  me@example.com
```

Target a single service with `connect.sh wizard firebase`.

> **It never logs in for you.** Passwords and two-factor codes should stay with the person who owns them, and login screens change often enough that automating them guarantees breakage. It guides you the whole way instead.

---

## What moves

| Item | How it travels |
|---|---|
| Skills, commands, agents, themes, plugins | Copied as files |
| `opencode.json` | Copied, with secret values replaced by placeholders |
| Global `AGENTS.md` | Copied as a file |
| `~/.claude/skills/` | Included — opencode reads this location automatically |
| Plugin dependencies (`package.json`) | Merged; opencode reinstalls them on next start |
| AI provider keys | **Not moved** — run `opencode auth login` on the new machine |
| GitHub / Firebase / Vercel / Supabase / Netlify | **Not moved** — log in again (the tool tells you which accounts) |
| Chat history, logs, `node_modules` | Not moved |

### Why credentials don't travel

Credentials are bound to accounts, not files.

- `gh` stores its token in the OS keychain — there is no file to copy in the first place.
- `firebase-tools.json` holds a plaintext refresh token; handing it to someone else hands them the account.
- Vercel uses per-repository tokens in `.env.production.local`, which travel with the repository.

So this tool records **which services were connected and under which account**, and on the new machine it checks what's installed and logged in, then prints only the commands still needed.

---

## Sharing with others

```bash
export.sh --mode share
```

Builds an archive without your global instructions or account details. If any secret or personal identifier (username, email, hostname) is found in an actual config file, **the archive is not created at all**. Exclude the offending file and try again:

```bash
export.sh --mode share --exclude my-private-script.sh
```

---

## Options

**export.sh**

| Option | Description |
|---|---|
| *(none)* | Personal transfer (default) |
| `--mode share` | Distribution build — excludes personal data, aborts if any is found |
| `--out <path>` | Where to write the archive |
| `--exclude <name>` | Leave out a file or folder |
| `--config-dir <path>` | Point at a specific config directory |
| `--force` | Proceed despite warnings |

**import.sh**

| Option | Description |
|---|---|
| *(none)* | Apply everything without asking (default) |
| `--ask` | Confirm each category |
| `--from <file>` | Read a tar.gz directly |

**connect.sh**

| Command | Description |
|---|---|
| `wizard [service]` | Guided connection, optionally for one service |
| `check` | Current connection status |

**connections.sh**

| Command | Description |
|---|---|
| `setup` | Print the logins still needed on this machine |
| `report` | Write current connections to a document |

---

## Safeguards

- **Allowlist, not denylist** — only listed items are packed, so nothing unexpected tags along.
- **`~/.local/share/opencode/` is never packed, under any option** — that's where API keys and chat history live.
- **Two-layer scan** — known key shapes, plus your own identifiers resolved at runtime.
- **Path templating** — home paths become `{{HOME}}` in the archive and are restored on import, so a different username still works.
- **Backup before import** — written to `~/.config/opencode/backups/import-<timestamp>/`.
- **Symlinks are dereferenced** — opencode does not follow symlinked skill folders, so contents are copied. Targets over 5 MB are excluded and recorded in `SYMLINKS.md` instead.
- **Timeouts on every external CLI call** — otherwise a pending login hangs the script with no explanation.

## Requirements

- macOS, Linux, or WSL (on Windows, WSL is the path opencode itself recommends)
- `bash`, `tar`, `rsync`, `python3`, `perl` — present on most systems
- [opencode](https://opencode.ai)

## License

MIT
