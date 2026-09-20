#!/usr/bin/env bash
# Periodically commit and push docs/data/live.json, so the published GitHub
# Pages dashboard (documents/decisions/0016-publish-docs-via-github-pages.md)
# reflects roughly-current data.
#
# Deliberately on its own timer, separate from sync-segments.sh's 60-second
# cadence: pushing every 60s would spam the commit history for no benefit
# (the goal is "roughly current", not real-time -- see that ADR's "影響"
# section on this exact gap).
#
# Only ever touches docs/data/live.json. Any other pending local changes in
# the repo (e.g. mid-edit ADR work) are left alone.
set -euo pipefail

export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_DIR="${TMPDIR:-/tmp}/kikimimi-publish-live-data.lock"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "another publish-live-data.sh is already running, skipping this tick"
  exit 0
fi
trap 'rmdir "$LOCK_DIR"' EXIT

cd "$REPO_DIR"

# In case other work (e.g. from the session that edits/pushes this repo
# directly) landed on origin since this machine's last pull. Fast-forward
# only -- if that fails because of real divergence, fail loudly rather than
# merge/rebase unattended.
git fetch origin main
git merge --ff-only origin/main

git add docs/data/live.json

if git diff --cached --quiet -- docs/data/live.json; then
  log "no change to docs/data/live.json, nothing to publish"
  exit 0
fi

git commit -m "docs: refresh live data ($(date -u +"%Y-%m-%dT%H:%M:%SZ"))" -- docs/data/live.json
git push origin main
log "pushed live data update"
