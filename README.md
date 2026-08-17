# claude-gorp

A Claude Code plugin for [gorp](https://github.com/nlaz/gorp), ranked
semantic code search built for agents. Grep can only find code you can
already name; gorp takes an identifier, a phrase, or a whole question and
returns the most relevant locations. This plugin installs the binary and
teaches Claude to reach for it.

## Install

In Claude Code:

```
/plugin marketplace add nlaz/claude-gorp
/plugin install claude-gorp@claude-gorp
```

The first session after installing downloads one ~48 MB self-contained
binary (checksum-verified, no sudo) into `~/.claude/plugins/data/claude-gorp/`.
That's the whole setup — no daemon, no GPU, no index step.

## What it does

- **Every session start**, a hook makes sure a gorp binary exists and
  injects a short search-guidance block into Claude's context, so Claude
  prefers ranked search over regex guessing for "where is X handled?"-style
  questions. The wording is adapted from gorp's README, where it is
  [measured, not decorative](https://github.com/nlaz/gorp#point-your-agent-at-it).
- **`/claude-gorp:gorp <query>`** runs a search directly, and the same
  skill gives Claude the full flag reference (`--json`, `-k`, globs,
  context lines, exact mode, cache management) when it needs more than a
  basic query.
- **Caching is on**: searches run through a wrapper that sets
  `GORP_AUTO_INDEX=1`, so the first ranked search in a repo warms a cache
  under `~/.cache/gorp` (bounded at 2 GiB, always revalidated against the
  live tree) and later searches answer in ~10–20 ms.

## How the binary is resolved

In order:

1. A `gorp` already on your PATH — used as-is, nothing downloaded.
2. The plugin-managed binary at `~/.claude/plugins/data/claude-gorp/libexec/gorp`.
3. Otherwise, download the pinned release
   (`gorp-<target>.tar.gz` + `.sha256` from
   [gorp releases](https://github.com/nlaz/gorp/releases)), verify the
   checksum, and install to the plugin data dir.

If the download fails (offline, GitHub down), the hook stays quiet, never
blocks the session, and retries on a later session start (at most once per
hour). Set `GORP_VERSION` (a tag, or `latest`) to override the pin.

## Requirements

macOS or Linux, arm64 or x86_64 — the targets gorp publishes binaries for.
On anything else (Windows included) the plugin no-ops cleanly.

## A note on the prompt wording

gorp's README ships a system-prompt block whose wording is measured — one
clause moved an agent's ranked-search share from 7% to 98%. This plugin
injects that block with only the opening clause adapted (the original says
gorp is the *only* search tool, which isn't true inside Claude Code, where
Grep and Glob exist). Everything from "Give it anything…" on is
byte-identical. If you want to re-verify the adapted wording, gorp's
`GORP_TRACE_FILE` telemetry plus the
[gorp-bench](https://github.com/nlaz/gorp-bench) harness measure
ranked-search share directly.

## Updating and uninstalling

- Plugin: `/plugin marketplace update claude-gorp`, then reinstall/update
  as Claude Code prompts.
- Binary: delete `~/.claude/plugins/data/claude-gorp/libexec/gorp` and
  start a new session (re-downloads the version pinned by the plugin), or
  run the ensure script with `GORP_VERSION=latest`.
- Uninstall: `/plugin uninstall claude-gorp`; the data dir and gorp's own
  cache are yours to remove (`rm -rf ~/.claude/plugins/data/claude-gorp`,
  `gorp cache --clear` or `rm -rf ~/.cache/gorp` beforehand).

## Security posture

The hook downloads only from `github.com/nlaz/gorp` releases, pins a
version, verifies the published sha256, never sudos, and writes only to
the plugin data dir (plus gorp's own cache under `~/.cache/gorp` once you
search). The checksum guards against corruption, not a compromised host —
the same posture as gorp's own `install.sh`.

## License

MIT (see [LICENSE](LICENSE)), matching gorp.
