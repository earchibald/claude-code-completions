#!/usr/bin/env bash
# Convenience installer for claude-completions.
#
#   ./install.sh            generate and install completions
#   ./install.sh --rc       also add the activation lines to your shell rc
#
# Everything it does is also available directly: ./claude-completions install

set -euo pipefail

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
TOOL=$HERE/claude-completions
MARKER='# >>> claude-completions >>>'
END_MARKER='# <<< claude-completions <<<'

[ -x "$TOOL" ] || { chmod +x "$TOOL" 2>/dev/null || true; }
[ -f "$TOOL" ] || { echo "install.sh: claude-completions not found next to this script" >&2; exit 1; }

DO_RC=''
ARGS=()
for a in "$@"; do
    case $a in
        --rc) DO_RC=1 ;;
        *) ARGS+=("$a") ;;
    esac
done

"$TOOL" install ${ARGS+"${ARGS[@]}"}

[ -n "$DO_RC" ] || exit 0

# Ask the tool where it installed things, rather than re-deriving the defaults
# here and drifting from them.
eval "$("$TOOL" paths)"

# Append a block once, identified by a marker pair.
add_block() {
    local rc=$1 body=$2
    [ -f "$rc" ] || touch "$rc"
    if grep -qF "$MARKER" "$rc"; then
        echo "install.sh: $rc already configured, leaving it alone"
        return 0
    fi
    {
        printf '\n%s\n' "$MARKER"
        printf '%s\n' "$body"
        printf '%s\n' "$END_MARKER"
    } >> "$rc"
    echo "install.sh: updated $rc"
}

if command -v bash >/dev/null 2>&1; then
    # macOS terminals start login shells, which read .bash_profile, not .bashrc.
    rc=$HOME/.bashrc
    if [ "$(uname -s)" = Darwin ] && [ -f "$HOME/.bash_profile" ]; then
        rc=$HOME/.bash_profile
    fi
    add_block "$rc" "[ -r $BASH_FILE ] && . $BASH_FILE"
fi

if command -v zsh >/dev/null 2>&1; then
    add_block "$HOME/.zshrc" "fpath=($ZSH_DIR \$fpath)
autoload -Uz compinit && compinit"
fi

echo
echo 'Open a new shell to pick up the completions.'
