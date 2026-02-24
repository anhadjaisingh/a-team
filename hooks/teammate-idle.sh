#!/usr/bin/env bash
# TeammateIdle hook — prevents teammates from going idle before their PR is ready
# Exit code 0: allow idle
# Exit code 2: send feedback, keep teammate working

set -euo pipefail

# Get the teammate's current branch
BRANCH=$(git branch --show-current 2>/dev/null || echo "")

if [ -z "$BRANCH" ] || [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  # Not on a feature branch — allow idle
  exit 0
fi

# Check if a PR exists for this branch
PR_NUMBER=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number' 2>/dev/null || echo "")

if [ -z "$PR_NUMBER" ]; then
  # No PR created yet — check if there are unpushed commits
  UNPUSHED=$(git log --oneline "origin/${BRANCH}..HEAD" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$UNPUSHED" -gt 0 ] 2>/dev/null; then
    echo "You have $UNPUSHED unpushed commits but haven't created a PR yet. Push your branch and create a PR before going idle."
    exit 2
  fi

  # Check if branch has commits ahead of base
  BASE_BRANCH=$(git rev-parse --abbrev-ref "$(git config --get "branch.${BRANCH}.merge" 2>/dev/null || echo "origin/main")" 2>/dev/null || echo "main")
  AHEAD=$(git rev-list --count "${BASE_BRANCH}..HEAD" 2>/dev/null || echo "0")
  if [ "$AHEAD" -gt 0 ]; then
    echo "Your branch has $AHEAD commits but no PR. Push your branch and create a PR before going idle."
    exit 2
  fi

  # No commits, no PR — teammate may legitimately be done or hasn't started
  exit 0
fi

# PR exists — check CI status
CI_STATUS=$(gh pr checks "$PR_NUMBER" --json bucket --jq '[.[] | .bucket] | if any(. == "fail") then "failing" elif any(. == "pending") then "pending" else "passing" end' 2>/dev/null || echo "unknown")

case "$CI_STATUS" in
  failing)
    echo "CI is failing on PR #${PR_NUMBER}. Check 'gh pr checks ${PR_NUMBER}' and fix the failures before going idle."
    exit 2
    ;;
  pending)
    echo "CI is still running on PR #${PR_NUMBER}. Wait for checks to complete and verify they pass before going idle."
    exit 2
    ;;
  passing)
    # All good — teammate can go idle
    exit 0
    ;;
  *)
    # Unknown state — allow idle but warn
    exit 0
    ;;
esac
