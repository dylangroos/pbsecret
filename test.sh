#!/bin/bash
# Acceptance tests for pbsecret. Saves and restores the real clipboard.
set -u
PB=${PB:-$(cd "$(dirname "$0")" && pwd)/pbsecret}
saved=$(pbpaste)
trap 'printf "%s" "$saved" | pbcopy' EXIT

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

# Bad variable name is rejected
printf 'v4lue' | pbcopy
"$PB" 'bad-name' -- true >/dev/null 2>&1
check "rejects bad name" "2" "$?"

# Scenario: Agent hands a generated secret to the user
out=$(echo s3cr3t | "$PB" --copy)
check "copy message" "copied 6 bytes" "$out"
check "copy clipboard" "s3cr3t" "$(pbpaste)"

echo "--- $fails failure(s)"
exit $fails
