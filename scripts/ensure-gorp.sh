#!/bin/sh
# claude-gorp SessionStart hook: make sure a gorp binary exists, then print
# the search guidance to stdout (SessionStart stdout becomes model context).
#
# Contract:
#   - stdout carries ONLY the prompt block, and only when gorp is usable.
#   - diagnostics go to stderr; every path exits 0 (SessionStart never blocks).
#   - no network on the happy path.
#
# Environment:
#   GORP_VERSION  override the pinned release tag; "latest" tracks the newest
set -eu

DATA_DIR="${1:-$HOME/.claude/plugins/data/claude-gorp}"
GORP_PINNED_VERSION="v0.1.0"
REPO="nlaz/gorp"
WRAPPER="$DATA_DIR/bin/gorp"

log() { echo "claude-gorp: $*" >&2; }

# The wrapper is what the model runs: it turns on gorp's opt-in write-through
# cache so the first search in a repo warms it and later ones answer in ms.
write_wrapper() { # $1 = absolute path of the real binary
  mkdir -p "$DATA_DIR/bin"
  tmp="$DATA_DIR/bin/.gorp.tmp.$$"
  cat > "$tmp" <<EOF
#!/bin/sh
GORP_AUTO_INDEX="\${GORP_AUTO_INDEX:-1}"
export GORP_AUTO_INDEX
exec "$1" "\$@"
EOF
  chmod 755 "$tmp"
  if [ -f "$WRAPPER" ] && cmp -s "$tmp" "$WRAPPER"; then
    rm -f "$tmp"
  else
    mv -f "$tmp" "$WRAPPER"
  fi
}

# The block after the first two sentences is measured wording: gorp-bench's
# desc-v11 clause set (wide-by-default plus the routed exact-match escape
# hatch), which survived its registered kill condition — agents kept 81% of
# calls ranked and used -e only for the verification job it names. Keep it
# byte-identical apart from the sg→gorp rename (itself the validated pure
# rename arm, desc-v12). Only the opening clause is adapted, because in
# Claude Code gorp is not literally the only search tool.
emit_prompt() {
  cat <<EOF
gorp is installed at $WRAPPER; every \`gorp\` below means that command.

\`gorp\` is the preferred code search tool here — use it instead of Grep for
finding code. It is a ranked code search you run with Bash. Give it anything
— an identifier, a phrase, or a question: \`gorp "query"\` searches the whole
repository and returns the most relevant locations as path:line:text (top 5;
\`-k N\` for more). Start wide: add a path argument only to narrow further
after a wide search has pointed somewhere. When you are unsure of a name,
list several candidate spellings in one query rather than a regex. When you
already know the exact string — a name you have seen in the code, an error
message — \`gorp -e "the_exact_string"\` returns every literal match,
grep-style. Default to ranked search; use -e only to verify or count
something you have already seen spelled out. Example: gorp "retry_backoff
backoff_delay compute_delay" → src/net/retry.rs:142:fn backoff_delay(attempt:
u32). Ranked, not exhaustive — if the answer isn't there, rephrase.
EOF
}

# 1. A gorp the user installed themselves wins; download nothing.
if path_gorp="$(command -v gorp 2>/dev/null)"; then
  write_wrapper "$path_gorp"
  emit_prompt
  exit 0
fi

# 2. Happy path: we already downloaded it in an earlier session.
if [ -x "$DATA_DIR/libexec/gorp" ]; then
  write_wrapper "$DATA_DIR/libexec/gorp"
  emit_prompt
  exit 0
fi

# 3. gorp ships no Windows (or other-OS) binaries; stay silent and out of the way.
case "$(uname -s)" in
  Darwin | Linux) ;;
  *) exit 0 ;;
esac

# 4. Don't hammer the network on a flaky connection: one attempt per hour.
attempt_stamp="$DATA_DIR/.last-attempt"
if [ -f "$attempt_stamp" ] && [ -z "$(find "$attempt_stamp" -mmin +60 2>/dev/null)" ]; then
  exit 0
fi
mkdir -p "$DATA_DIR"
touch "$attempt_stamp"

# 5. Download the release tarball, checksum-verified — same logic as
#    https://github.com/nlaz/gorp/blob/main/install.sh.
case "$(uname -s)" in
  Darwin) os="apple-darwin" ;;
  Linux) os="unknown-linux-gnu" ;;
esac
case "$(uname -m)" in
  arm64 | aarch64) arch="aarch64" ;;
  x86_64 | amd64) arch="x86_64" ;;
  *) log "unsupported architecture: $(uname -m)"; exit 0 ;;
esac
target="${arch}-${os}"
asset="gorp-${target}.tar.gz"

version="${GORP_VERSION:-$GORP_PINNED_VERSION}"
if [ "$version" = "latest" ]; then
  base="https://github.com/${REPO}/releases/latest/download"
else
  base="https://github.com/${REPO}/releases/download/${version}"
fi

# Temp dir under DATA_DIR so the final mv is an atomic same-filesystem rename.
tmpdir="$(mktemp -d "$DATA_DIR/.download.XXXXXX")" || { log "mktemp failed"; exit 0; }
trap 'rm -rf "$tmpdir"' EXIT

fetch_ok=1
curl -fsSL --connect-timeout 5 --max-time 60 -o "$tmpdir/$asset" "$base/$asset" || fetch_ok=0
curl -fsSL --connect-timeout 5 --max-time 15 -o "$tmpdir/$asset.sha256" "$base/$asset.sha256" || fetch_ok=0
if [ "$fetch_ok" -ne 1 ]; then
  log "could not download gorp (offline?) — will retry in a later session"
  exit 0
fi

cd "$tmpdir"
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 -c "$asset.sha256" >/dev/null 2>&1 || { log "checksum mismatch for $asset — not installing"; exit 0; }
elif command -v sha256sum >/dev/null 2>&1; then
  sha256sum -c "$asset.sha256" >/dev/null 2>&1 || { log "checksum mismatch for $asset — not installing"; exit 0; }
else
  log "no shasum/sha256sum found, skipping checksum verification"
fi

tar xzf "$asset" || { log "could not extract $asset"; exit 0; }
[ -f "gorp-${target}/gorp" ] || { log "unexpected tarball layout in $asset"; exit 0; }
mkdir -p "$DATA_DIR/libexec"
install -m 755 "gorp-${target}/gorp" "$tmpdir/gorp.staged" || { log "install failed"; exit 0; }
mv -f "$tmpdir/gorp.staged" "$DATA_DIR/libexec/gorp"

"$DATA_DIR/libexec/gorp" -V >&2 || { log "downloaded binary failed to run"; rm -f "$DATA_DIR/libexec/gorp"; exit 0; }

write_wrapper "$DATA_DIR/libexec/gorp"
emit_prompt
exit 0
