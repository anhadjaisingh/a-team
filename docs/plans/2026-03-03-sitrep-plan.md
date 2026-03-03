# /sitrep Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `/sitrep` slash command that gives an intelligent status update when picking up work mid-context in any git repo.

**Architecture:** Single skill with two modes — brief (default, sequential single-agent scan) and full (`--full` flag, 4 parallel Explore subagents). Command file delegates to skill. Brief mode ends with an offer to expand.

**Tech Stack:** Claude Code skill (markdown prompt), Explore subagents, `gh` CLI, git

---

### Task 1: Create the SKILL.md

**Files:**
- Create: `skills/sitrep/SKILL.md`

**Step 1: Create the skill directory**

```bash
mkdir -p skills/sitrep
```

**Step 2: Write SKILL.md**

Create `skills/sitrep/SKILL.md` with the following content:

```markdown
---
name: sitrep
description: "Use when picking up work mid-context or when the user asks for a status update. Gives an intelligent situation report covering git state, tasks, plans, GitHub PRs/issues, and prior session memory."
---

# Sitrep — Situation Report

Give the user an intelligent status update on the current project. Two modes: brief (default) and full (with `--full` flag).

**Announce at start:** "Running sitrep..."

## Detect Mode

Check if the user passed `--full` as an argument.

- **No argument or anything other than `--full`:** Run Brief Mode.
- **`--full` passed:** Run Full Mode.

---

## Brief Mode (Default)

Gather surface-level information sequentially. Do NOT read plan doc contents — just list them. Do NOT spawn subagents. Keep it fast.

### Step 1: Git State

Run these commands and note the results:

` `` bash
# Current branch and short status
git branch --show-current
git status --short

# Last 5 commits (one-line)
git log --oneline -5

# How far ahead/behind the default branch
git rev-list --left-right --count main...HEAD 2>/dev/null || git rev-list --left-right --count master...HEAD 2>/dev/null
` ``

### Step 2: Task List

Check for active Claude tasks:

- Call the TaskList tool
- If tasks exist, note their subjects and statuses
- If no tasks, skip this section

### Step 3: Plan Docs

` ``bash
# List plan files with dates
ls -lt docs/plans/*.md 2>/dev/null
` ``

Just list the filenames — do NOT read their contents in brief mode.

### Step 4: GitHub State

` ``bash
# Open PRs for this repo
gh pr list --state open --limit 5 2>/dev/null

# Open issues
gh issue list --state open --limit 5 2>/dev/null
` ``

If `gh` is not authenticated or not available, skip this section and note it.

### Step 5: Auto-Memory

Check for Claude auto-memory files for the current project:

- Look in `~/.claude/projects/` for a directory matching the current project path
- If a `MEMORY.md` exists there, read it for any relevant prior context
- If memory files reference in-progress work or decisions, note them

### Step 6: Synthesize Brief Report

Combine all findings into a **3-5 line summary**. Format:

```
**Sitrep:** On `{branch}`, {N} ahead of {base}. {uncommitted status}.
{task summary if any — e.g., "3/5 tasks done, 2 pending."}
{plan summary — e.g., "2 plan docs found, latest: {name}."}
{github summary — e.g., "1 open PR (#42, CI passing), 2 open issues."}
{memory context if relevant — e.g., "Last session was working on auth middleware."}
```

Then offer: "Want the full report? Say yes or run `/sitrep --full`."

---

## Full Mode (`--full`)

Spawn 4 parallel Explore subagents, each investigating a domain. Wait for all results, then synthesize a structured report.

### Step 1: Spawn Parallel Agents

Launch all 4 agents simultaneously using the Agent tool with `subagent_type: "Explore"`. Each agent gets a specific investigation prompt:

**Agent 1: git-scout**
```
Investigate the git state of this repository thoroughly.

Report on:
1. Current branch name and how it relates to main/master
2. Commits ahead/behind the default branch — list them with short messages
3. Uncommitted changes (staged and unstaged) — summarize what files are affected
4. Recent activity: last 10 commits across all branches with dates
5. Stale branches: any branches not touched in 7+ days
6. Any merge conflicts or rebase state
7. Tags: latest tag if any

Format your findings as structured markdown sections.
```

**Agent 2: plan-analyst**
```
Investigate all plan/design documents and task state for this project.

1. Read every file in docs/plans/ (and any similar directories like docs/designs/, docs/specs/)
2. For each plan document:
   - What is the goal?
   - How many tasks/phases does it have?
   - For each task/phase, check if it appears to be implemented by searching the codebase:
     - Look for files mentioned in the plan
     - Check if functions/classes described exist
     - Look for test files that correspond to planned features
   - Classify each task/phase as: DONE, IN PROGRESS, NOT STARTED, or UNCLEAR
3. Check the Claude TaskList for any active tasks and their statuses
4. Note any TODOs or FIXMEs in recently modified files

Format your findings as a per-plan breakdown with task-level status.
```

**Agent 3: github-intel**
```
Investigate the GitHub state of this repository using the gh CLI.

Report on:
1. Open PRs: title, number, author, CI status, review status, age
   Command: gh pr list --state open --json number,title,author,statusCheckRollup,reviewDecision,createdAt
2. Recently merged PRs (last 5): what landed recently
   Command: gh pr list --state merged --limit 5 --json number,title,mergedAt
3. Open issues: title, number, labels, assignees
   Command: gh issue list --state open --json number,title,labels,assignees
4. Latest CI run status on the default branch
   Command: gh run list --branch main --limit 3 (or master)
5. Any draft PRs or PRs with failing CI that need attention

If gh is not available or not authenticated, report that clearly.

Format your findings as structured markdown with sections per category.
```

**Agent 4: memory-recall**
```
Investigate Claude's auto-memory and any saved context for this project.

1. Find the auto-memory directory for the current project:
   - Check ~/.claude/projects/ for directories matching the current project path
   - The path encoding replaces / with - (e.g., /Users/foo/projects/bar becomes -Users-foo-projects-bar)
2. Read MEMORY.md if it exists — note any in-progress work, decisions, or patterns
3. Read any other .md files in the memory directory (e.g., debugging.md, patterns.md)
4. Check for any CLAUDE.md files in the project root or .claude/ directory — these contain project-specific instructions and context
5. Look for any TODO.md, CHANGELOG.md, or similar status-tracking files in the project root

Summarize: what was the user working on, what decisions were made, what context should carry forward.

Format your findings as a narrative summary with key points highlighted.
```

### Step 2: Collect and Synthesize

Wait for all 4 agents to complete. Then synthesize their findings into a structured report:

```markdown
# Sitrep — Full Report

## Current Status
{From git-scout: branch, last activity, uncommitted changes}

## Task Progress
{From plan-analyst TaskList data: what's done, pending, blocked}
{Include specific task subjects and statuses}

## Plan Progress
{From plan-analyst: per-plan breakdown}
### {Plan Name}
- Phase 1: {status} — {brief description}
- Phase 2: {status} — {brief description}
...

## GitHub State
{From github-intel: PRs, issues, CI}
### Open PRs
- #{N}: {title} — {CI status}, {review status}
### Open Issues
- #{N}: {title} — {labels}

## Context from Prior Sessions
{From memory-recall: what was being worked on, key decisions}

## Suggested Next Steps
{Your synthesis: prioritized list of what to do next based on ALL findings}
1. {Most urgent item — e.g., "Fix failing CI on PR #42"}
2. {Next priority — e.g., "Continue Phase 3 of auth plan"}
3. {Follow-up — e.g., "Address Issue #38 re: token expiry"}
```

The "Suggested Next Steps" section is YOUR synthesis — connect the dots across all sources. Prioritize:
1. Blockers and failing CI first
2. In-progress work that's close to completion
3. Planned work that hasn't started
4. Open issues and future work
```

**Step 3: Commit**

```bash
git add skills/sitrep/SKILL.md
git commit -m "feat: add sitrep skill for intelligent status reports"
```

---

### Task 2: Create the Command File

**Files:**
- Create: `commands/sitrep.md`

**Step 1: Write the command file**

Create `commands/sitrep.md` with the following content:

```markdown
---
description: "Get an intelligent status update on the current project. Use --full for a detailed parallel investigation."
---

Invoke the a-team:sitrep skill and follow it exactly as presented to you.

Pass through any arguments the user provided (e.g., `--full`).
```

Note: Unlike `execute-team.md`, this command does NOT use `disable-model-invocation: true` because the skill needs Claude to actively gather information and synthesize.

**Step 2: Commit**

```bash
git add commands/sitrep.md
git commit -m "feat: add /sitrep slash command"
```

---

### Task 3: Update plugin.json

**Files:**
- Modify: `.claude-plugin/plugin.json`

**Step 1: Update keywords**

Add `"sitrep"` and `"status-report"` to the keywords array in `.claude-plugin/plugin.json`:

```json
{
  "name": "a-team",
  "description": "Team-driven development: orchestrate Claude Code agent teams to execute plans in parallel with PR-based workflows",
  "version": "0.2.0",
  "author": {
    "name": "Anhad Jai Singh"
  },
  "repository": "https://github.com/anhadjaisingh/a-team",
  "license": "MIT",
  "keywords": ["agent-teams", "orchestration", "parallel-development", "pr-workflow", "sitrep", "status-report"]
}
```

Note: Bump version from 0.1.0 to 0.2.0 since we're adding a new feature.

**Step 2: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump version and add sitrep keywords to plugin manifest"
```

---

### Task 4: Verification

**Step 1: Verify file structure**

```bash
# Check all files exist
ls -la skills/sitrep/SKILL.md
ls -la commands/sitrep.md
cat .claude-plugin/plugin.json
```

**Step 2: Verify skill frontmatter is valid**

```bash
# Check SKILL.md starts with valid YAML frontmatter
head -4 skills/sitrep/SKILL.md
```

Expected:
```
---
name: sitrep
description: "Use when picking up work mid-context or when the user asks for a status update..."
---
```

**Step 3: Verify command file frontmatter**

```bash
head -4 commands/sitrep.md
```

Expected:
```
---
description: "Get an intelligent status update on the current project. Use --full for a detailed parallel investigation."
---
```

**Step 4: Verify git state is clean**

```bash
git status
git log --oneline -5
```

All changes should be committed. No uncommitted files.
