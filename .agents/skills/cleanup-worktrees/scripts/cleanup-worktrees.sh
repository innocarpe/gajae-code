#!/usr/bin/env bash
# Repo-local post-task worktree hygiene for gajae-code contributor agents.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: cleanup-worktrees.sh [options]

Remove a completed-task git worktree in this monorepo. Keep the feature branch
while a PR is open; delete local + origin after merge (or fully-merged into base).

Options:
  --path <dir>        Worktree path to remove.
  --branch <name>     Branch whose worktree should be removed (if registered).
  --current           Use the current checkout if it is a linked worktree.
  --remote <name>     Remote for branch deletion (default: origin).
  --base <branch>     Base for merge checks (default: upstream/dev, origin/dev,
                      origin/main, origin/master).
  --delete-branch     Delete local (+ origin) branch even without a merged PR.
  --force-branch      Use git branch -D instead of -d.
  --allow-dirty       Allow removing a dirty worktree.
  --dry-run           Print actions only.
  -h, --help          Show help.
USAGE
}

path=""
branch=""
use_current=0
remote="origin"
base=""
delete_branch=0
force_branch=0
allow_dirty=0
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)
      [[ $# -ge 2 && "${2:-}" != --* ]] || { echo "--path requires a directory." >&2; exit 2; }
      path="${2:-}"; shift 2 ;;
    --branch)
      [[ $# -ge 2 && "${2:-}" != --* ]] || { echo "--branch requires a name." >&2; exit 2; }
      branch="${2:-}"; shift 2 ;;
    --current) use_current=1; shift ;;
    --remote)
      [[ $# -ge 2 && "${2:-}" != --* ]] || { echo "--remote requires a name." >&2; exit 2; }
      remote="${2:-}"; shift 2 ;;
    --base)
      [[ $# -ge 2 && "${2:-}" != --* ]] || { echo "--base requires a branch." >&2; exit 2; }
      base="${2:-}"; shift 2 ;;
    --delete-branch) delete_branch=1; shift ;;
    --force-branch) force_branch=1; shift ;;
    --allow-dirty) allow_dirty=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

run() {
  if [[ "$dry_run" -eq 1 ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

is_protected_branch() {
  case "$1" in
    main|master|dev|develop|staging|production|prod|HEAD) return 0 ;;
    release/*|worktree/*) return 0 ;;
  esac
  return 1
}

abs_path() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p"
  else
    (cd "$p" && pwd -P)
  fi
}

if [[ -n "$path" ]]; then
  [[ -d "$path" ]] || { echo "Path does not exist: $path" >&2; exit 1; }
  path="$(abs_path "$path")"
  git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { echo "Not a git worktree: $path" >&2; exit 1; }
elif [[ "$use_current" -eq 1 || -z "$branch" ]]; then
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { echo "Not inside a git worktree; pass --path or --branch." >&2; exit 1; }
  path="$(abs_path "$(git rev-parse --show-toplevel)")"
elif [[ -n "$branch" ]]; then
  path=""
else
  echo "Specify --path, --branch, or --current." >&2
  exit 2
fi

discover_root_from() {
  local start="$1"
  local common
  common="$(git -C "$start" rev-parse --git-common-dir)"
  if [[ "$common" != /* ]]; then
    common="$(cd "$start" && cd "$common" && pwd -P)"
  else
    common="$(cd "$common" && pwd -P)"
  fi
  if [[ "$(basename "$common")" == ".git" ]]; then
    abs_path "$(dirname "$common")"
  else
    abs_path "$(dirname "$common")"
  fi
}

if [[ -n "$path" ]]; then
  primary_root="$(discover_root_from "$path")"
else
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { echo "Need a repo context for --branch without --path." >&2; exit 1; }
  primary_root="$(discover_root_from "$(git rev-parse --show-toplevel)")"
fi

primary_from_list="$(git -C "$primary_root" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')"
if [[ -n "${primary_from_list:-}" ]]; then
  primary_root="$(abs_path "$primary_from_list")"
fi

if [[ -z "$branch" && -n "$path" ]]; then
  branch="$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [[ "$branch" == "HEAD" ]] && branch=""
fi

if [[ -z "$path" && -n "$branch" ]]; then
  cand=""
  while IFS= read -r line; do
    case "$line" in
      worktree\ *) cand="${line#worktree }" ;;
      branch\ refs/heads/*)
        b="${line#branch refs/heads/}"
        if [[ "$b" == "$branch" ]]; then
          path="$(abs_path "$cand")"
          break
        fi
        ;;
    esac
  done < <(git -C "$primary_root" worktree list --porcelain)
fi

echo "primary_root=$primary_root"
echo "target_path=${path:-none}"
echo "target_branch=${branch:-none}"

if [[ -n "$path" ]]; then
  if [[ "$(abs_path "$path")" == "$(abs_path "$primary_root")" ]]; then
    echo "Refusing to remove the primary checkout: $path" >&2
    exit 1
  fi

  registered=0
  while IFS= read -r line; do
    if [[ "$line" == worktree\ * ]]; then
      wt="$(abs_path "${line#worktree }" 2>/dev/null || true)"
      if [[ -n "$wt" && "$wt" == "$(abs_path "$path")" ]]; then
        registered=1
      fi
    fi
  done < <(git -C "$primary_root" worktree list --porcelain)

  if [[ "$registered" -ne 1 ]]; then
    echo "Path is not a registered linked worktree of $primary_root: $path" >&2
    exit 1
  fi

  if [[ "$allow_dirty" -ne 1 ]]; then
    if [[ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]]; then
      echo "Worktree is dirty: $path (pass --allow-dirty to override)" >&2
      exit 1
    fi
  fi

  cwd="$(pwd -P 2>/dev/null || pwd)"
  case "$cwd" in
    "$path"|"$path"/*) run cd "$primary_root" ;;
  esac

  echo "Removing worktree: $path"
  if [[ "$allow_dirty" -eq 1 ]]; then
    run git -C "$primary_root" worktree remove --force "$path"
  else
    run git -C "$primary_root" worktree remove "$path"
  fi
  run git -C "$primary_root" worktree prune
  echo "worktree: removed"
else
  echo "worktree: none found for branch (branch rules may still apply)"
fi

if [[ -z "$branch" ]]; then
  echo "branch: skipped (unknown)"
  exit 0
fi

if is_protected_branch "$branch"; then
  echo "branch: kept (protected: $branch)"
  exit 0
fi

still_checked_out=0
still_path=""
cand=""
while IFS= read -r line; do
  case "$line" in
    worktree\ *) cand="$(abs_path "${line#worktree }" 2>/dev/null || true)" ;;
    branch\ refs/heads/*)
      b="${line#branch refs/heads/}"
      if [[ "$b" == "$branch" ]]; then
        still_checked_out=1
        still_path="$cand"
      fi
      ;;
  esac
done < <(git -C "$primary_root" worktree list --porcelain)

if [[ "$still_checked_out" -eq 1 ]]; then
  echo "branch: kept (still checked out at ${still_path:-unknown})"
  exit 0
fi

pr_state=""
pr_url=""
pr_number=""
if command -v gh >/dev/null 2>&1; then
  pr_json="$(gh pr list --state all --head "$branch" --json number,state,url,headRefName,mergedAt --limit 5 2>/dev/null || true)"
  if [[ -n "$pr_json" && "$pr_json" != "[]" ]]; then
    if command -v python3 >/dev/null 2>&1; then
      pr_state="$(printf '%s' "$pr_json" | python3 -c 'import json,sys; j=json.load(sys.stdin); p=j[0] if j else {}; print(p.get("state",""))')"
      pr_url="$(printf '%s' "$pr_json" | python3 -c 'import json,sys; j=json.load(sys.stdin); p=j[0] if j else {}; print(p.get("url",""))')"
      pr_number="$(printf '%s' "$pr_json" | python3 -c 'import json,sys; j=json.load(sys.stdin); p=j[0] if j else {}; print(p.get("number") or "")')"
    else
      pr_state="$(printf '%s' "$pr_json" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p' | head -1)"
      pr_url="$(printf '%s' "$pr_json" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p' | head -1)"
      pr_number="$(printf '%s' "$pr_json" | sed -n 's/.*"number":\([0-9]*\).*/\1/p' | head -1)"
    fi
  fi
fi

pr_state_norm="$(printf '%s' "$pr_state" | tr '[:lower:]' '[:upper:]')"
should_delete=0
keep_reason=""

if [[ "$delete_branch" -eq 1 ]]; then
  should_delete=1
elif [[ "$pr_state_norm" == "OPEN" ]]; then
  should_delete=0
  keep_reason="open PR${pr_number:+ #$pr_number}${pr_url:+ ($pr_url)}"
elif [[ "$pr_state_norm" == "MERGED" ]]; then
  should_delete=1
elif [[ "$pr_state_norm" == "CLOSED" ]]; then
  should_delete=0
  keep_reason="PR closed without merge${pr_number:+ #$pr_number}; pass --delete-branch to drop"
else
  should_delete=0
  keep_reason="no open/merged PR detected; keep branch (use --delete-branch after merge)"
fi

if [[ "$should_delete" -eq 0 && "$pr_state_norm" != "OPEN" ]]; then
  if [[ -z "$base" ]]; then
    for candidate in "upstream/dev" "origin/dev" "upstream/main" "origin/main" "origin/master"; do
      if git -C "$primary_root" rev-parse --verify "$candidate" >/dev/null 2>&1; then
        base="$candidate"
        break
      fi
    done
  fi
  if [[ -n "$base" ]] && git -C "$primary_root" show-ref --verify --quiet "refs/heads/$branch"; then
    if git -C "$primary_root" merge-base --is-ancestor "refs/heads/$branch" "$base" 2>/dev/null; then
      should_delete=1
      keep_reason=""
      echo "branch fully merged into $base"
    fi
  fi
fi

if [[ "$should_delete" -ne 1 ]]; then
  echo "branch: kept ($keep_reason)"
  exit 0
fi

if git -C "$primary_root" show-ref --verify --quiet "refs/heads/$branch"; then
  if [[ "$force_branch" -eq 1 ]]; then
    run git -C "$primary_root" branch -D "$branch"
  else
    if ! run git -C "$primary_root" branch -d "$branch"; then
      echo "branch: local delete refused by git branch -d (not fully merged). Use --force-branch if intentional." >&2
      exit 1
    fi
  fi
  echo "branch: local deleted ($branch)"
else
  echo "branch: local already gone ($branch)"
fi

if git -C "$primary_root" show-ref --verify --quiet "refs/remotes/${remote}/${branch}"; then
  run git -C "$primary_root" push "$remote" --delete "$branch"
  echo "branch: ${remote}/${branch} deleted"
else
  echo "branch: no ${remote}/${branch}"
fi

if [[ -n "$pr_url" ]]; then
  echo "pr: $pr_state $pr_url"
fi
