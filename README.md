# pbsecret

Hand secrets to a coding agent (Claude Code, Codex, etc.) through the macOS clipboard, without the value ever landing in the agent's context.

```sh
# You: copy a token. Agent runs:
pbsecret GITHUB_TOKEN -- curl -s -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/user
#   -> $GITHUB_TOKEN is set for that one command
#   -> any occurrence of the value in stdout/stderr is printed as ***
#   -> the clipboard is cleared

# Agent generated a secret you need? It runs:
openssl rand -hex 20 | pbsecret --copy
#   -> "copied 40 bytes"; the value is on your clipboard, not in the transcript
```

pbsecret stores nothing itself. The clipboard is the only transport, and it is emptied after each read.

## Install

```sh
git clone https://github.com/dylangroos/pbsecret.git
ln -s "$PWD/pbsecret/pbsecret" ~/.local/bin/pbsecret   # any dir on your PATH
```

Requires macOS (`pbcopy`/`pbpaste`) and the system `bash` and `perl`.

## Tell your agent about it

Add to `~/.claude/CLAUDE.md` (or `AGENTS.md`):

```markdown
# Secrets
- Never ask me to paste a secret into chat, and never print one. When a command needs a secret, ask me to copy it, then run `pbsecret NAME -- <cmd>` (sets `$NAME` for that command only, masks it in output, clears the clipboard). One secret per call.
- To hand me a secret you generated, pipe it: `<cmd> | pbsecret --copy`. Then tell me it is on my clipboard.
```

## Behavior

- Exit code is the command's own (128+N if killed by signal N). `TERM`, `HUP` and `INT` sent to pbsecret are forwarded to the command.
- pbsecret exits when the command exits, even if a background process it started still holds stdout/stderr open.
- These checks run **before** the clipboard is cleared, so a mistake does not use up the secret:
  - exit 2 if the clipboard is empty, `NAME` is not a valid variable name, or `NAME` is `PATH`, `IFS`, `DYLD_*` or `LD_*`
  - exit 2 if no line of the value has 4+ characters (too short to mask without garbling the output)
  - exit 127 if the command is not found
- `NAME` is set only in the command's environment, never in pbsecret's own.
- Multi-line secrets (PEM keys, JSON credentials) are masked line by line; lines shorter than 4 characters are not masked.
- Output streams through as it arrives. Only a tail that could be the start of the secret is held back until the next write, so a secret split across two writes is still masked.
- `--copy` marks the clipboard item with the `org.nspasteboard.ConcealedType` and `TransientType` markers, so clipboard managers that honor [nspasteboard.org](http://nspasteboard.org) (Maccy, Raycast, etc.) do not keep it.

## Limits

This prevents **accidental** leaks into an agent's transcript. It is not a boundary against a hostile agent: anything that can run `pbpaste` can read your clipboard. Masking catches exact matches only — a base64-encoded or truncated copy of the secret is printed as-is.

The clipboard is not a private channel:
- When **you** copy a secret, your clipboard manager may keep it in its history. pbsecret clears the clipboard after reading it but cannot remove history entries.
- Universal Clipboard can send the clipboard to your other Apple devices.
- `SIGKILL` cannot be forwarded. If pbsecret is killed with it, the command keeps running.

## Test

```sh
./test.sh
```

The test overwrites the clipboard during the run. At exit it restores plain text only. Images, files and rich text on the clipboard are lost.
