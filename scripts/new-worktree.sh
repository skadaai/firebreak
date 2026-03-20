#!/usr/bin/env bash
set -euo pipefail

log() { printf '[new-worktree] %s\n' "$*" >&2; }

branch="${1:-}"
shift || true

if [[ -z "$branch" ]]; then
  log "ERROR: Branch name is empty"
  exit 1
fi

root="$(git rev-parse --show-toplevel)"
parent="$(cd "$root/.." && pwd)"

log "Repo root: $root"
log "Worktree parent: $parent"
log "Branch: $branch"

# Ensure 'root' is the main worktree
# so relative worktree links are computed from the primary repo's gitdir.
if [[ "$(git -C "$root" rev-parse --git-common-dir)" != ".git" ]]; then
  log "ERROR: Run this from the primary checkout (the one whose git-common-dir is .git)."
  log "       Current git-common-dir: $(git -C "$root" rev-parse --git-common-dir)"
  exit 1
fi

wt="$parent/$branch"
log "Computed branch: $branch"
log "Worktree path: $wt"

if [[ -e "$wt" ]]; then
  log "ERROR: Target path already exists: $wt"
  exit 1
fi

# Ensure Git will create portable worktree links.
# Per Git docs, --relative-paths overrides worktree.useRelativePaths.
git -C "$root" config worktree.useRelativePaths true

# If branch exists already, just attach it. Otherwise create a new branch in the new worktree.
if git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
  log "Branch already exists; attaching existing branch."
  git -C "$root" worktree add --relative-paths "$wt" "$branch" >/dev/null
else
  log "Creating new worktree from main (detached) and creating branch inside it."
  # Detached avoids 'main already used by worktree' errors.
  git -C "$root" worktree add --relative-paths --detach "$wt" main >/dev/null
  git -C "$wt" switch -c "$branch" >/dev/null
fi

# # Shared dirs live in repo root; symlink them into the new worktree.
# for d in ".direnv" ".codex" ".claude"; do
#   [[ -e "$root/$d" ]] || mkdir -p "$root/$d"
#   ln -sfnr "$root/$d" "$wt/$d"
# done

# Copy env files best-effort (no failure if none exist)
log "Copying .env* from repo root into new worktree (best-effort)..."
shopt -s nullglob
copied_any=0
for f in "$root"/.env*; do
  [[ -f "$f" ]] || continue
  base="$(basename "$f")"
  if [[ -e "$wt/$base" ]]; then
    log "Skip (already exists): $base"
    continue
  fi
  log "Copy: $base"
  cp -f "$f" "$wt/$base"
  copied_any=1
done
shopt -u nullglob

if [[ "$copied_any" = "0" ]]; then
  log "No .env* files found in repo root; skipping."
fi

cat <<EOF
Worktree ready:
  cd "$wt"
  direnv allow
EOF
