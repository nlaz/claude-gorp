---
name: gorp
description: >
  Reference for gorp, the ranked code search tool. Use when a basic gorp query
  isn't enough: JSON output for scripting, more results, scoping to paths or
  globs, context lines, cache management, or when a search isn't finding what
  you expect.
argument-hint: "[query]"
allowed-tools: "Bash(gorp *), Bash(*/gorp *)"
---

# gorp — ranked code search

If the user invoked this as `/gorp <query>`, run that query first:
`gorp "<query>"` and show the results.

## Basics

`gorp "<query>" [paths…]` — the query is an identifier, a phrase, or a whole
question; paths default to the current directory. Output is ranked
`path:line:text` blocks, top 5 by default. Start wide: search the whole repo
first, add a path argument only to narrow after a wide search has pointed
somewhere. Results are ranked, not exhaustive — a miss means rephrase, not
give up. The binary's location is stated in the session context if `gorp`
isn't on PATH.

## More results and scoping

- `-k N` — return N results (default 5; bare `-k` means 20)
- positional paths — `gorp "query" src/ lib/` limits the scope
- `-g GLOB` — keep only matching paths, repeatable (`-g '*.py'`). A single
  `*` does not cross `/`: scope to a directory with `-g 'src/**'`, or more
  simply pass the directory as a path argument
- with a path argument, printed paths are relative to that scope root, not
  to the current directory
- `-l` — matching paths only, in rank order
- `--lines A-B` — keep only results in a line range
- `-M N` — truncate printed lines at N characters (default 200)

## Context and output

- `-C N` / `-A N` / `-B N` — context lines around each hit
- `--json` — JSONL, one object per hit: `path`, `start_line`, `end_line`,
  `line`, `text`, `score` (plus optional fields). Example:
  `gorp --json -k 20 "auth middleware" . | jq -r '.path' | sort -u`
- stdout carries only results and pipes cleanly; hints and footers ride on
  stderr. Exit codes: 0 = hits, 1 = no hits (not an error — rephrase and
  retry), 2 = real error (e.g. a missing path).

## Exact matches

When you need every occurrence of a known literal string or identifier —
for example, every call site before a rename — `gorp -e '<regex>'` runs an
exact regex search with grep semantics (every match, not a ranking).
`-i` ignore case, `-F` literal string, `-w` whole words, `-c` per-file
counts, `--all` uncapped output. For everything else, ranked search is the
better default.

## Cache

Searches run with `GORP_AUTO_INDEX=1` (the plugin's wrapper sets it), so the
first ranked search in a repo warms a cache under `~/.cache/gorp` and later
searches answer in milliseconds. The cache is bounded at 2 GiB and always
revalidated against the live tree, so results reflect the code as it is now.

- `gorp cache` — show what the cache holds; `--prune` reclaims, `--clear` empties
- `GORP_CACHE_DIR` — relocate the cache; `GORP_CACHE_MAX_BYTES` — resize the budget
- `GORP_NO_HINTS=1` — silence stderr hints

## Updating and troubleshooting

The plugin-managed binary lives at `~/.claude/plugins/data/claude-gorp/libexec/gorp`
(a `gorp` already on PATH is preferred and left alone). To upgrade the
managed binary, delete that file and start a new session, or run
`GORP_VERSION=latest <plugin>/scripts/ensure-gorp.sh` by hand. If a session
started offline, gorp may be absent; it installs itself on a later session
start.
