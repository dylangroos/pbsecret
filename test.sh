#!/bin/bash
# Acceptance tests for pbsecret. Saves and restores the plain-text clipboard.
set -u
PB=${PB:-$(cd "$(dirname "$0")" && pwd)/pbsecret}
saved=$(pbpaste; printf x)
saved=${saved%x}
trap 'printf "%s" "$saved" | pbcopy' EXIT
tmp=$(mktemp -d)

fails=0
check() { # name expected actual
  if [ "$2" == "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "     want: $2"; echo "     got:  $3"; fails=$((fails+1)); fi
}

# Scenario: Agent uses a copied secret without seeing it
printf 'ghp_abc123\n' | pbcopy
out=$("$PB" TOKEN -- sh -c 'echo got $TOKEN' 2>&1)
check "masks stdout" "got ***" "$out"
check "clears clipboard" "" "$(pbpaste)"

# stderr is masked too, and stays on stderr
printf 'ghp_abc123' | pbcopy
err=$("$PB" TOKEN -- sh -c 'echo "err $TOKEN" >&2' 2>&1 >/dev/null)
check "masks stderr" "err ***" "$err"

# Exit code of the child comes back
printf 'x1234' | pbcopy
"$PB" TOKEN -- sh -c 'exit 7' >/dev/null 2>&1
check "propagates exit code" "7" "$?"

# Multi-line secret (PEM-like): every long line is masked
printf -- '-----BEGIN KEY-----\nAAAABBBBCCCC\n-----END KEY-----\n' | pbcopy
out=$("$PB" KEY -- sh -c 'printf "%s\n" "$KEY"')
check "masks multi-line" "$(printf '***\n***\n***')" "$out"

# Scenario: Empty clipboard stops the command
pbcopy </dev/null
out=$("$PB" TOKEN -- echo should-not-run 2>&1); code=$?
check "empty exit code" "2" "$code"
check "empty message" "pbsecret: clipboard is empty" "$out"

# Bad variable name is rejected, and the clipboard is kept
printf 'v4lue' | pbcopy
"$PB" 'bad-name' -- true >/dev/null 2>&1
check "rejects bad name" "2" "$?"
check "bad name keeps clipboard" "v4lue" "$(pbpaste)"

# Names that change how commands load are rejected
"$PB" PATH -- true >/dev/null 2>&1
check "rejects PATH" "2" "$?"
"$PB" DYLD_INSERT_LIBRARIES -- true >/dev/null 2>&1
check "rejects DYLD_*" "2" "$?"

# NAME is set only in the child, so it cannot break the masker
printf 'ghp_secretvalue' | pbcopy
out=$("$PB" PERL5OPT -- sh -c 'echo "[$PERL5OPT]"' 2>&1)
check "PERL5OPT stays in child" "[***]" "$out"

# Value too short to mask safely is rejected, and the clipboard is kept
printf 'x' | pbcopy
"$PB" K -- echo 'exit max index' >/dev/null 2>&1
check "rejects short value" "2" "$?"
check "short value keeps clipboard" "x" "$(pbpaste)"
printf '\nab\ncd' | pbcopy
out=$("$PB" K -- printf 'line1\nab cd\n' 2>/dev/null); code=$?
check "rejects multi-line with no long line" "2" "$code"
check "no output when rejected" "" "$out"

# Missing command stops before the clipboard is cleared
printf 'abcd1234' | pbcopy
"$PB" K -- no-such-cmd-xyz >/dev/null 2>&1
check "missing command exit code" "127" "$?"
check "missing command keeps clipboard" "abcd1234" "$(pbpaste)"

# Background processes that hold the pipes do not block the exit
printf 'abcd1234' | pbcopy
start=$(date +%s)
out=$("$PB" K -- sh -c 'sleep 5 & echo done')
elapsed=$(( $(date +%s) - start ))
check "background child output" "done" "$out"
check "does not wait for background child" "yes" "$([ $elapsed -lt 3 ] && echo yes || echo "no (${elapsed}s)")"

# TERM is forwarded to the child
printf 'abcd1234' | pbcopy
"$PB" K -- sh -c 'echo $$ > "$0"; exec sleep 30' "$tmp/pid" >/dev/null 2>&1 &
pbpid=$!
sleep 1
kill -TERM $pbpid
wait $pbpid; code=$?
sleep 0.3
check "TERM exit code" "143" "$code"
check "TERM reaches child" "gone" "$(kill -0 "$(cat "$tmp/pid")" 2>/dev/null && echo alive || echo gone)"

# Output without a newline is shown before the command exits
printf 'abcd1234' | pbcopy
"$PB" K -- sh -c 'printf "50%%\r"; sleep 2; echo end' > "$tmp/progress" &
p=$!
sleep 1
check "flushes partial line" "50%" "$(tr -d '\r' < "$tmp/progress")"
wait $p

# A secret split across two writes is still masked
printf 'ghp_abc123' | pbcopy
out=$("$PB" K -- sh -c 'printf "x ghp_"; sleep 0.5; printf "abc123 y\n"')
check "masks secret split across writes" "x *** y" "$out"

# Scenario: Agent hands a generated secret to the user
out=$(echo s3cr3t | "$PB" --copy)
check "copy message" "copied 6 bytes" "$out"
check "copy clipboard" "s3cr3t" "$(pbpaste)"
types=$(osascript -l JavaScript -e 'ObjC.import("AppKit"); ObjC.deepUnwrap($.NSPasteboard.generalPasteboard.types).join(" ")')
[[ $types == *org.nspasteboard.ConcealedType* ]] && concealed=yes || concealed="no ($types)"
check "copy marks concealed" "yes" "$concealed"

rm -rf "$tmp"
echo "--- $fails failure(s)"
exit $fails
