#!/usr/bin/env zsh
# Validate a generated zsh completion without needing a terminal.
#
# It stubs _arguments, then parses each spec against the grammar zsh actually
# uses:  OPT[description]:message:action
#
#   * the description must be terminated by an unescaped ]
#   * what follows the description must be empty or start with :
#   * a (...) action must have balanced parentheses
#   * a function action must name a function that exists
#
# Parentheses inside a description are literal to zsh and are not checked.
#
# Usage: validate-zsh.zsh <path to _claude>

emulate -L zsh

# The generated functions read these; outside a real completion they are unset.
local curcontext='' context='' state='' state_descr='' line=''
typeset -A opt_args

local file=$1
local -a BAD
integer nspec=0

# Completion functions zsh provides that our stub environment will not define.
local -a KNOWN_ACTIONS
KNOWN_ACTIONS=(_files _default _describe _normal _message _nothing _values
               _directories _command_names _hosts)

# Split SPEC into description / message / action, reporting any grammar error.
check_spec() {
    local s=$1
    integer i=1 n=${#s}
    local ch desc='' rest=''

    # option name, up to an unescaped [ or :
    while (( i <= n )); do
        ch=${s[i]}
        [[ $ch == '\' ]] && { (( i += 2 )); continue }
        [[ $ch == '[' || $ch == ':' ]] && break
        (( i++ ))
    done

    if [[ ${s[i]} == '[' ]]; then
        (( i++ ))
        integer start=i closed=0
        while (( i <= n )); do
            ch=${s[i]}
            [[ $ch == '\' ]] && { (( i += 2 )); continue }
            [[ $ch == ']' ]] && { closed=1; break }
            (( i++ ))
        done
        (( closed )) || { BAD+=("description not terminated -> $s"); return }
        desc=${s[start,i-1]}
        (( i++ ))
    fi

    rest=${s[i,n]}
    [[ -z $rest ]] && return
    if [[ $rest != :* ]]; then
        BAD+=("trailing junk after description -> $s")
        return
    fi

    # :message:action  — message may not contain an unescaped colon
    local body=${rest#:}
    local action=${body#*:}
    [[ $body == *:* ]] || return   # ":" alone means "value required, no completion"

    [[ -z $action ]] && return

    if [[ $action == '('* ]]; then
        local o=${#action//[^\(]/} c=${#action//[^\)]/}
        (( o == c )) || BAD+=("unbalanced () in action -> $s")
        return
    fi

    # A leading space means the action is a command with arguments.
    local fn=${${action# }%% *}
    if [[ $fn == _* ]]; then
        (( $+functions[$fn] )) || (( ${KNOWN_ACTIONS[(I)$fn]} )) ||
            BAD+=("missing function $fn -> $s")
    fi
}

_arguments() {
    local s
    for s in "$@"; do
        [[ $s == -[sCAS] ]] && continue
        (( nspec++ ))
        check_spec "$s"
    done
}
_describe() { : }
_files()    { : }
_default()  { : }

source $file 2>/dev/null

local -a argfns
argfns=(${(k)functions[(I)_claude_args_*]})
(( ${#argfns} )) || BAD+=('no _claude_args_* functions were defined')

local f
for f in $argfns; do $f 2>/dev/null; done

local ref
for f in ${(k)functions[(I)_claude_dispatch_*]}; do
  for ref in ${(u)${(M)${(z)functions[$f]}:#_claude_args_*}}; do
    (( $+functions[$ref] )) || BAD+=("dispatcher $f references missing $ref")
  done
done

print "arg functions: ${#argfns}"
print "specs checked: $nspec"
if (( ${#BAD} )); then
  print "PROBLEMS: ${#BAD}"
  print -l -- ${BAD[1,20]}
  exit 1
fi
print 'ALL OK'
