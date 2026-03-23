#!/usr/bin/env bash
set -euo pipefail

log() { printf '[new-worktree] %s\n' "$*" >&2; }

branch="${1:-}"
shift || true
worktree_name="${1:-}"
shift || true

if [[ -z "$branch" ]]; then
  log "ERROR: Branch name is empty"
  exit 1
fi

root="$(git rev-parse --show-toplevel)"
base_ref="${FIREBREAK_WORKTREE_BASE_REF:-main}"
if [[ -n "$worktree_name" ]]; then
  worktree_parent="${FIREBREAK_TASK_WORKTREE_ROOT:-${FIREBREAK_WORKTREE_ROOT:-}}"
else
  worktree_name="$branch"
  worktree_parent="${FIREBREAK_TASK_WORKTREE_ROOT:-${FIREBREAK_WORKTREE_ROOT:-}}"
fi

if [[ -z "$worktree_parent" ]]; then
  sibling_parent="$(cd "$root/.." && pwd)"
  if [[ -w "$sibling_parent" ]]; then
    worktree_parent="$sibling_parent"
  else
    state_root="${FIREBREAK_TASK_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/firebreak/tasks}"
    worktree_parent="$state_root/worktrees"
  fi
fi

mkdir -p "$worktree_parent"
shared_root="${FIREBREAK_TASK_SHARED_ROOT:-${FIREBREAK_WORKTREE_SHARED_ROOT:-$(cd "$worktree_parent/.." && pwd)}}"

log "Repo root: $root"
log "Worktree parent: $worktree_parent"
log "Shared root: $shared_root"
log "Branch: $branch"
log "Worktree name: $worktree_name"
log "Base ref: $base_ref"

# Ensure 'root' is the main worktree
# so relative worktree links are computed from the primary repo's gitdir.
if [[ "$(git -C "$root" rev-parse --git-common-dir)" != ".git" ]]; then
  log "ERROR: Run this from the primary checkout (the one whose git-common-dir is .git)."
  log "       Current git-common-dir: $(git -C "$root" rev-parse --git-common-dir)"
  exit 1
fi

wt="$worktree_parent/$worktree_name"
log "Computed branch: $branch"
log "Worktree path: $wt"

if [[ -e "$wt" ]]; then
  log "ERROR: Target path already exists: $wt"
  exit 1
fi

mkdir -p "$(dirname "$wt")"

# If branch exists already, just attach it. Otherwise create a new branch in the new worktree.
if git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
  log "Branch already exists; attaching existing branch."
  git -C "$root" worktree add "$wt" "$branch" >/dev/null
else
  log "Creating new worktree from $base_ref (detached) and creating branch inside it."
  # Detached avoids '<base ref> already used by worktree' errors.
  git -C "$root" worktree add --detach "$wt" "$base_ref" >/dev/null
  git -C "$wt" switch -c "$branch" >/dev/null
fi

# Shared dirs live above the worktree root so tasks can reuse agent state.
for d in ".direnv" ".codex" ".claude"; do
  shared_path="$shared_root/$d"
  if [[ ! -e "$shared_path" && ! -L "$shared_path" ]]; then
    mkdir -p "$shared_path"
  fi
  ln -sfnr "$shared_path" "$wt/$d"
done

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
