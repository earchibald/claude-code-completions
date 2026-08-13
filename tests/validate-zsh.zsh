#!/usr/bin/env zsh
# Validate a generated zsh completion without needing a terminal.
#
#  1. Every _arguments spec has balanced [] and ().
#  2. Every completion function a spec names actually exists.
#  3. Every dispatcher branch points at a function that exists.
#
# Usage: validate-zsh.zsh <path to _claude>

emulate -L zsh

# The generated functions read these; outside a real completion they are unset.
local curcontext='' context='' state='' state_descr='' line=''
typeset -A opt_args

local file=$1
local -a BAD
integer nspec=0

local -a BUILTIN_ACTIONS
BUILTIN_ACTIONS=(_files _default _describe _normal _message _nothing)

_arguments() {
  local s
  for s in "$@"; do
    [[ $s == -[sCAS] ]] && continue
    (( nspec++ ))

    local open=${#s//[^\[]/} close=${#s//[^\]]/}
    (( open != close )) && BAD+=("unbalanced [] -> $s")
    local po=${#s//[^\(]/} pc=${#s//[^\)]/}
    (( po != pc )) && BAD+=("unbalanced () -> $s")

    if [[ $s == *:_[a-zA-Z_]* ]]; then
      local fn=${${s##*:}%% *}
      if [[ $fn == _* ]] && ${BUILTIN_ACTIONS[(r)$fn]:+false} true; then
        (( $+functions[$fn] )) || BAD+=("missing function $fn -> $s")
      fi
    fi
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
