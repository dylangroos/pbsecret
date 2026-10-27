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

Nothing is stored. The clipboard is the only transport, and it is emptied after each read.

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

- Exit code is the command's own (127 if not found, 128+N if killed by signal N).
- Exits 2 without running anything if the clipboard is empty or `NAME` is not a valid variable name.
- Multi-line secrets (PEM keys, JSON credentials) are masked line by line; lines shorter than 4 characters are not masked.
- Output passes through line-buffered, so a prompt without a trailing newline appears when the command exits.

## Limits

This prevents **accidental** leaks into an agent's transcript. It is not a boundary against a hostile agent: anything that can run `pbpaste` can read your clipboard. Masking catches exact matches only — a base64-encoded or truncated copy of the secret is printed as-is.

## Test

```sh
./test.sh   # overwrites the clipboard during the run, restores it at exit
```
