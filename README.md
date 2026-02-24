# a-team

A [Claude Code](https://claude.com/claude-code) plugin for team-driven development. Orchestrates parallel agent teams to execute implementation plans, with each teammate owning tasks end-to-end — from implementation through PR creation and CI verification.

Designed as a companion to the [superpowers](https://github.com/obra/superpowers) plugin, adding a third execution method alongside `subagent-driven-development` and `executing-plans`.

## Requirements

- Claude Code with the [agent teams](https://code.claude.com/docs/en/agent-teams) feature enabled
- [GitHub CLI](https://cli.github.com/) (`gh`) authenticated
- [superpowers](https://github.com/obra/superpowers) plugin installed (referenced skills)

Enable agent teams in your `settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

## Installation

Add the marketplace and install the plugin:

```
/plugin marketplace add anhadjaisingh/a-team
/plugin install a-team@a-team
```

## Usage

After creating an implementation plan (e.g., via superpowers' `/write-plan` or `/brainstorm`), run:

```
/execute-team
```

Or specify a plan file directly:

```
/execute-team docs/plans/2026-02-25-my-feature.md
```

The TL agent will:

1. **Setup** — Detect and configure pre-commit hooks, create git worktrees for each teammate
2. **Spawn** — Create an agent team with one teammate per task group
3. **Monitor** — Stay free for your interaction while teammates work in parallel
4. **Merge** — Spawn a PR shepherd to rebase and merge PRs in dependency order
5. **Cleanup** — Verify everything landed, clean up worktrees and the team

## How It Works

### Agent Roles

| Role | Responsibility |
|---|---|
| **TL (you)** | Orchestrates, monitors, answers questions. Never implements. |
| **Teammates** | Implement tasks with TDD, create PRs, fix CI until green. |
| **PR Shepherd** | Rebases and merges PRs in correct dependency order. |

### Pre-commit Hooks

The TL auto-detects your project's linter, formatter, and build tools and sets up local pre-commit hooks so teammates catch CI issues before pushing. If existing hooks are detected, it asks before modifying anything.

### Quality Gates

Two Claude Code hooks enforce discipline:

- **TeammateIdle** — Prevents teammates from going idle before their PR is CI-green
- **TaskCompleted** — Verifies code is committed before marking tasks complete

## Plugin Structure

```
a-team/
├── .claude-plugin/
│   ├── plugin.json          # Plugin manifest
│   └── marketplace.json     # Marketplace catalog
├── skills/
│   └── team-driven-development/
│       ├── SKILL.md             # TL orchestration (main skill)
│       ├── teammate-prompt.md   # Spawn prompt for worker agents
│       └── pr-shepherd-prompt.md # Spawn prompt for merge agent
├── commands/
│   └── execute-team.md      # /execute-team slash command
└── hooks/
    ├── hooks.json           # Hook wiring
    ├── teammate-idle.sh     # TeammateIdle hook
    └── task-completed.sh    # TaskCompleted hook
```

## License

MIT
