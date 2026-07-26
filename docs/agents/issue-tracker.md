# Issue tracker: GitHub

Issues and PRDs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`.
- **Read an issue**: `gh issue view <number> --comments`, also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments` with appropriate label and state filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply or remove labels**: `gh issue edit <number> --add-label "..."` or `--remove-label "..."`
- **Close an issue**: `gh issue close <number> --comment "..."`

Infer the repository from `git remote -v`; `gh` does this automatically when run inside the checkout.

## Pull requests as a triage surface

**PRs as a request surface: no.**

When changed to `yes`, external pull requests run through the same labels and states as issues. Read them with `gh pr view` and `gh pr diff`, and manage them with the corresponding `gh pr` commands.

GitHub shares one number space across issues and pull requests. Resolve a bare issue number with `gh pr view <number>` and fall back to `gh issue view <number>`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

The `/wayfinder` map is one issue with child issues as decision tickets.

- **Map**: label it `wayfinder:map`.
- **Child ticket**: link it as a GitHub sub-issue. If sub-issues are unavailable, link it from a task list and add `Part of #<map>` to the child.
- **Blocking**: use GitHub native issue dependencies. If unavailable, add `Blocked by: #<number>` to the child.
- **Frontier**: select the first open, unassigned child with no open blockers.
- **Claim**: assign the issue to the active developer.
- **Resolve**: record the answer in a comment, close the child, and update the map's decisions.
