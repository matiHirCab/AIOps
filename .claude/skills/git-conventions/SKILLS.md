---
name: git-conventions
description: Apply this team's git branching and commit message conventions. Use whenever
             the user asks to name a branch, write a commit message, review a commit,
             create a PR title, or asks "how should I name this", "what type is this commit",
             "is this branch name correct", or anything related to git workflow. Also trigger
             when the user describes a change and needs help figuring out the right commit
             type or branch structure.
---

# Git Conventions

## Branch Naming

Branches are **feature branches based off `develop`**.

**Format:** `tipo/issue-id/description`

| Part | Values | Notes |
|---|---|---|
| `tipo` | `feature`, `fix`, `chore` | Same criteria as commit types |
| `issue-id` | Ticket ID (ClickUp, GitHub, Trello…) | **Optional** — depends on the project |
| `description` | Short English summary | `kebab-case` |

**Examples:**
```
feature/234/add-user-form
fix/398/infinite-redirect
chore/delete-comments
```

**Rules:**
- Always branch from `develop`
- Skip `issue-id` segment entirely if the project doesn't use tickets (don't leave an empty slot)
- Description should be short and meaningful, not generic

---

## Commit Messages

Format follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

**Format:** `type: short description`  
**With scope (optional):** `type(scope): short description`

### Commit Types

| Type | Use for |
|---|---|
| `feat` | New functionality |
| `fix` | Bug fixes |
| `refactor` | Internal improvement, no visible behavior change |
| `chore` | Maintenance tasks — scripts, deps, config |
| `docs` | Documentation changes |
| `style` | Code formatting/style (not CSS, not visual) |

### Scope (optional)

Specifies the affected part of the system, in parentheses after the type:

```
feat(auth): add login endpoint
fix(home): prevent infinite redirect
refactor(api): simplify response parser
docs(readme): update setup instructions
```

### Rules

- All commit messages must be in **English**
- Use **present tense** — `add`, not `added`; `fix`, not `fixed`
- Be specific — avoid `fix bug`, `update code`, `changes`, etc.
- don't ever put yourself (coding assistant) as co-author. 

**Examples:**
```
feat: add login endpoint
fix: prevent infinite redirect
refactor: simplify response parser
docs: update README with setup steps
```

---

## Choosing the Right Type

When the user describes a change, use this decision flow:

1. **Does it add something the user can see or use?** → `feat`
2. **Does it fix something broken?** → `fix`
3. **Does it restructure/clean code with no behavior change?** → `refactor`
4. **Is it deps, config, scripts, tooling?** → `chore`
5. **Only docs changed?** → `docs`
6. **Only whitespace/formatting?** → `style`

---

## When Helping the User

- If they describe a change, suggest both the branch name AND commit message
- If `issue-id` is unclear, ask or omit it
- If scope is unclear, default to omitting it (it's optional)
- Always output examples in code blocks so they're easy to copy
