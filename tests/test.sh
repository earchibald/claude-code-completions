#!/usr/bin/env bash
# Test suite for claude-completions.
#
# Runs against a fake `claude` that serves the real help pages but reports a
# version we control. That lets the version-awareness paths be tested without
# installing several Claude Code releases.
#
# Usage: tests/test.sh

set -uo pipefail

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd -- "$HERE/.." && pwd)
TOOL=$ROOT/claude-completions

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export XDG_CACHE_HOME=$WORK/cache
export CLAUDE_COMPLETIONS_BASH_DIR=$WORK/bash
export CLAUDE_COMPLETIONS_ZSH_DIR=$WORK/zsh

PASS=0
FAIL=0

ok()   { printf '  ok   %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; FAIL=$((FAIL + 1)); }

check() { # check <name> <expected-substring> <actual>
    case "$3" in
        *"$2"*) ok "$1" ;;
        *) bad "$1" "expected to contain: $2
       got: $3" ;;
    esac
}

# --- fake claude -------------------------------------------------------------

command -v claude >/dev/null 2>&1 || { echo 'test.sh: needs a real claude in PATH'; exit 1; }

mkdir -p "$WORK/bin"
cat > "$WORK/bin/claude" <<'FEOF'
#!/usr/bin/env bash
REAL=$REAL_CLAUDE
if [ "$1" = "--version" ]; then echo "${FAKE_VERSION:-9.9.9} (Claude Code)"; exit 0; fi
out=$("$REAL" "$@" 2>/dev/null)
if [ -n "${FAKE_EXTRA_FLAG:-}" ] && [ "$1" = "--help" ]; then
  out=$(printf '%s\n' "$out" | awk -v e="  --zzz-test-flag <x>                   A flag that only exists in tests" '
    /^  --add-dir/ && !d { print e; d=1 } { print }')
fi
printf '%s\n' "$out"
FEOF
chmod +x "$WORK/bin/claude"
export REAL_CLAUDE
REAL_CLAUDE=$(command -v claude)
export CLAUDE_BIN=$WORK/bin/claude

# --- generation --------------------------------------------------------------

echo 'generation'
out=$(FAKE_VERSION=1.0.0 "$TOOL" install --force 2>&1)
check 'installs both shells' 'Installed' "$out"
[ -f "$WORK/bash/claude" ] && ok 'bash script written' || bad 'bash script written'
[ -f "$WORK/zsh/_claude" ] && ok 'zsh script written'  || bad 'zsh script written'

grep -q '^# claude-version: 1.0.0' "$WORK/bash/claude" && ok 'bash records version' || bad 'bash records version'
grep -q '^# spec-hash: [0-9a-f]\{64\}' "$WORK/bash/claude" && ok 'bash records spec hash' || bad 'bash records spec hash'

# --- bash behaviour ----------------------------------------------------------

echo 'bash completion'
comp() { # comp <words...> -> prints COMPREPLY
    local script=$WORK/bash/claude
    bash -c '
      source "$1"; shift
      COMP_WORDS=("$@"); COMP_CWORD=$(( $# - 1 ))
      COMP_LINE="$*"; COMP_POINT=${#COMP_LINE}
      COMPREPLY=(); _claude 2>/dev/null; printf "%s\n" "${COMPREPLY[*]}"
    ' _ "$script" "$@"
}

check 'top-level commands'  'mcp'          "$(comp claude '')"
check 'global flags'        '--effort'     "$(comp claude --eff)"
check 'model values'        'sonnet'       "$(comp claude --model '')"
check 'permission modes'    'bypassPermissions' "$(comp claude --permission-mode '')"
check 'output formats'      'stream-json'  "$(comp claude --output-format '')"
check 'comma lists'         'user,project' "$(comp claude --setting-sources user,)"
check 'nested subcommands'  'add-json'     "$(comp claude mcp '')"
check 'nested flags'        '--transport'  "$(comp claude mcp add --)"
check 'nested enum values'  'stdio'        "$(comp claude mcp add --transport '')"
check 'three levels deep'   'update'       "$(comp claude plugin marketplace '')"
check 'flags before a cmd'  'mcp'          "$(comp claude --model opus mc)"
check 'directory values'    '/'            "$(comp claude --add-dir /)"

# --- zsh behaviour -----------------------------------------------------------

echo 'zsh completion'
if command -v zsh >/dev/null 2>&1; then
    if zsh -n "$WORK/zsh/_claude" 2>/dev/null; then ok 'zsh script parses'; else bad 'zsh script parses'; fi
    vout=$(zsh "$HERE/validate-zsh.zsh" "$WORK/zsh/_claude" 2>&1)
    check 'zsh specs are well-formed' 'ALL OK' "$vout"
else
    echo '  skip zsh (not installed)'
fi

# --- version awareness -------------------------------------------------------

echo 'version awareness'
out=$(FAKE_VERSION=1.0.0 "$TOOL" install 2>&1)
check 'same version does nothing' 'Up to date' "$out"

cp "$WORK/bash/claude" "$WORK/snapshot"

out=$(FAKE_VERSION=1.1.0 "$TOOL" install 2>&1)
check 'new version, same surface' 'no command changes' "$out"

if diff <(grep -v '^# claude-version' "$WORK/snapshot") \
        <(grep -v '^# claude-version' "$WORK/bash/claude") >/dev/null; then
    ok 'body untouched when surface is unchanged'
else
    bad 'body untouched when surface is unchanged'
fi
grep -q '^# claude-version: 1.1.0' "$WORK/bash/claude" && ok 'version header bumped' || bad 'version header bumped'
grep -q '^# claude-version: 1.1.0' "$WORK/zsh/_claude" && ok 'zsh version header bumped' || bad 'zsh version header bumped'

out=$(FAKE_VERSION=1.2.0 FAKE_EXTRA_FLAG=1 "$TOOL" install 2>&1)
check 'surface change is detected' 'CLI surface changed' "$out"
check 'added flags are reported'   '--zzz-test-flag'     "$out"
check 'new flag completes'         '--zzz-test-flag'     "$(comp claude --zzz)"

out=$(FAKE_VERSION=1.3.0 "$TOOL" install 2>&1)
check 'removed flags are reported' 'removed:' "$out"

# --- housekeeping ------------------------------------------------------------

echo 'housekeeping'
check 'status reports version' '1.3.0' "$("$TOOL" status 2>&1)"
"$TOOL" uninstall >/dev/null 2>&1
[ -f "$WORK/bash/claude" ] && bad 'uninstall removes scripts' || ok 'uninstall removes scripts'

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
