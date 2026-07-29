---
name: cleanup-worktrees
description: >
  Repo-local post-task hygiene for gajae-code: always remove the session git
  worktree after work is done; keep the feature branch while a PR is open; delete
  local + origin branch after merge (or when fully merged into base). Use when a
  task finishes, a PR is opened, a PR merges/closes, or the user says "cleanup
  worktree" / "worktree 정리". This is a contributor agent skill — not a GJC
  product workflow skill (do not add to the four default bundled workflows).
---

# Cleanup Worktrees (gajae-code contributor hygiene)

## Scope

**This repository only.** Paths live under the repo root:

| Item | Path |
|------|------|
| Canonical skill | `.agents/skills/cleanup-worktrees/SKILL.md` |
| Script | `.agents/skills/cleanup-worktrees/scripts/cleanup-worktrees.sh` |
| Claude / Grok skill links | `.claude/skills/cleanup-worktrees`, `.grok/skills/cleanup-worktrees` |

Not a GJC default workflow skill. Do not install under `packages/coding-agent/src/defaults/gjc/skills` or treat as a fifth public workflow.

## Policy (default — do not wait to be asked)

When **this session's task is done** (tests green, PR opened, or user says done):

1. **Always remove** the linked worktree created for that task.
2. **PR still open** → keep local + remote branch.
3. **PR merged** (or branch fully merged into base) → also delete local branch and matching `origin` branch when safe.
4. **Never** remove the primary checkout, protected branches, or worktrees for **other** active work.

## Command

From the monorepo root (or any linked worktree of this repo):

```bash
# Prefer explicit path when known
./.agents/skills/cleanup-worktrees/scripts/cleanup-worktrees.sh --path /path/to/worktree

# By branch (removes registered worktree; keeps branch if PR open)
./.agents/skills/cleanup-worktrees/scripts/cleanup-worktrees.sh --branch fix/issue-1234-foo

# Preview
./.agents/skills/cleanup-worktrees/scripts/cleanup-worktrees.sh --branch fix/issue-1234-foo --dry-run

# After merge when force-dropping the branch is intended
./.agents/skills/cleanup-worktrees/scripts/cleanup-worktrees.sh --branch fix/issue-1234-foo --delete-branch
```

`gajae-code` PR base is usually **`dev`** (`upstream/dev` when both remotes exist). The script prefers `upstream/dev`, then `origin/dev`, then `main`/`master`.

## Agent procedure

1. `git worktree list` — identify the worktree for **this** task.
2. If your shell is inside that worktree, `cd` to the primary repo root first.
3. Run the script with `--path` or `--branch`.
4. Report removed path, branch kept/deleted, and any worktrees left alone.

## Safety (script-enforced)

- Refuse primary checkout removal.
- Refuse protected branches: `main`, `master`, `dev`, `develop`, `staging`, `production`, `prod`, `release/*`, `worktree/*`.
- Refuse dirty worktrees unless `--allow-dirty`.
- Soft-delete local branches (`git branch -d`); `-D` only with `--force-branch`.
- Do not bulk-delete unrelated worktrees.

## Decision table

| Situation | Worktree | Local branch | Origin branch |
|-----------|----------|--------------|---------------|
| Done, PR open | remove | keep | keep |
| Done, no PR, pushed | remove | keep | keep |
| PR merged / fully merged into base | remove | delete | delete |
| PR closed without merge | remove | keep (unless `--delete-branch`) | keep (unless `--delete-branch`) |
| Other session's worktree | leave | leave | leave |

## Not this skill

- GJC product workflows (`deep-interview`, `ralplan`, `ultragoal`, `team`)
- Long-lived `worktree/*` lane rebase tools outside this repo
