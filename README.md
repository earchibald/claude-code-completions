# claude-code-completions

Bash and zsh tab completion for the [Claude Code](https://claude.com/claude-code) CLI.

The Claude Code CLI ships no `completion` subcommand. This tool builds one by reading
`claude --help`, so the completions match the version you actually have installed.

| | |
|---|---|
| **Shells** | bash (3.2+), zsh |
| **Source of truth** | `claude --help`, walked recursively |
| **Updates** | version-aware; regenerates only when the CLI surface really changed |
| **Dependencies** | `awk`, `sed`, `sha256sum` or `shasum` — all standard |
| **Install target** | your home directory; nothing needs root |

## Install

### Homebrew

```sh
brew install earchibald/tap/claude-completions
claude-completions install
```

### From source

```sh
git clone https://github.com/earchibald/claude-code-completions
cd claude-code-completions
./install.sh --rc
```

`--rc` adds the activation lines to `~/.bashrc` (or `~/.bash_profile` on macOS) and
`~/.zshrc`. Drop it to print the lines instead and add them yourself. The Homebrew
formula does not touch your shell rc; `claude-completions install` prints the line
to add.

### Verifying a release

Tags are signed, and release tarballs are built reproducibly with `git archive`.

```sh
git tag -v v1.0.0                                  # signed tag
shasum -a 256 -c SHA256SUMS                        # published checksum
```

The Homebrew formula pins the release tarball by `sha256`, so Homebrew refuses to
install if the file ever changes.

Open a new shell, then press Tab:

```
$ claude --per<TAB>
$ claude --permission-mode <TAB>
acceptEdits  auto  bypassPermissions  manual  dontAsk  plan

$ claude mcp add --transport <TAB>
stdio  sse  http
```

## What it completes

| Context | Completions |
|---|---|
| `claude <Tab>` | every subcommand, including aliases such as `plugins` and `upgrade` |
| `claude --<Tab>` | every global flag |
| `claude mcp add --<Tab>` | flags for that exact subcommand, three levels deep |
| `--model`, `--fallback-model` | model aliases and full model IDs |
| `--permission-mode`, `--output-format`, `--input-format`, `--effort` | the allowed values |
| `--setting-sources`, `--tools`, `--allowed-tools`, `--disallowed-tools` | comma-separated list building |
| `--resume` | your 20 most recent session IDs for the current directory |
| `--agent` | agent names from `./.claude/agents` and `~/.claude/agents` |
| `--worktree` | local git branches |
| `--add-dir`, `--plugin-dir` | directories |
| `--settings`, `--mcp-config`, `--json-schema`, `--file` | files |

## Keeping it current

Re-run `claude-completions install` after you upgrade Claude Code. It is the update
path as well as the install path, and it does the least work that is correct:

| Situation | What happens |
|---|---|
| Same Claude version as last run | Nothing. Exits immediately. |
| New version, identical CLI surface | Records the new version. The completion scripts stay byte-identical. |
| New version, changed CLI surface | Regenerates, and reports which options were added or removed. |

The second row is the point of the design. Most Claude Code releases change no flags,
so a version bump alone must not churn your files. The tool hashes the parsed command
surface and compares it against the previous hash. Only a real difference triggers a
rewrite.

```
$ claude-completions install
Reading the CLI surface of claude 2.1.221 ...
claude 2.1.221: no command changes since 2.1.220. Version bumped, scripts untouched.

$ claude-completions install
Reading the CLI surface of claude 2.2.0 ...
claude 2.2.0: CLI surface changed since 2.1.221.
  added:   --new-flag
  removed: --old-flag
Installed ~/.local/share/bash-completion/completions/claude
```

Each generated script records its provenance in its header:

```
# generator-version: 1.0.0
# claude-version: 2.1.220
# spec-hash: 625a1970...
```

## Commands

```
claude-completions install [--shell bash|zsh] [--force] [--quiet]
claude-completions status
claude-completions generate [--shell bash|zsh] [-o FILE]
claude-completions uninstall
```

`generate` writes a script to stdout without installing it. Use it to inspect the
output or to vendor a completion file into another repo.

## Environment

| Variable | Purpose |
|---|---|
| `CLAUDE_BIN` | Path to the `claude` binary. Default: `claude` from `PATH`. |
| `CLAUDE_COMPLETIONS_BASH_DIR` | Where to write the bash script. Default: `$XDG_DATA_HOME/bash-completion/completions`. |
| `CLAUDE_COMPLETIONS_ZSH_DIR` | Where to write the zsh script. Default: `$XDG_DATA_HOME/zsh/site-functions`. |

## How it works

1. Run `claude --help`, then `claude <cmd> --help` for each command, to depth three.
2. Parse each page into a flat spec: options, whether each takes a value, its allowed
   values, and its description. Help text wraps across lines, so each entry is
   reflowed before it is parsed.
3. Enrich the spec from a small curated table at the top of `claude-completions`.
   The CLI publishes some enums machine-readably as `(choices: "a", "b")`; values it
   does not publish, such as model aliases, live in that table. Edit it if the CLI
   grows a value the parser cannot see.
4. Emit a bash script driven by `compgen`, and a zsh script driven by `_arguments`.

## Tests

```sh
./tests/test.sh
```

The suite runs against a fake `claude` that serves the real help pages but reports a
version the test controls. That exercises the version-awareness paths without needing
several Claude Code releases installed. It covers generation, bash completion
behaviour at every nesting depth, zsh spec validity, and all three update outcomes.

`tests/validate-zsh.zsh` checks the generated zsh script without a terminal: it stubs
`_arguments`, then verifies that every spec has balanced brackets and that every
completion function a spec names actually exists.

## Limitations

- Completions are only as good as `claude --help`. An undocumented flag will not appear.
- Enum values that the CLI does not publish need an entry in the curated table.
- `gateway` and `serve` are not walked, to avoid starting a long-running process.

## Licence

MIT
