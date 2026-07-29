---
description: Clean up completed-task git worktrees in this repo (keep branch if PR open; delete after merge)
---

Follow the repo skill at `.agents/skills/cleanup-worktrees/SKILL.md`.

Default policy: always remove this session's worktree when work is done; keep the branch while a PR is open; delete local + origin branch after merge.

```bash
./.agents/skills/cleanup-worktrees/scripts/cleanup-worktrees.sh --path <worktree>
./.agents/skills/cleanup-worktrees/scripts/cleanup-worktrees.sh --branch <branch>
```
