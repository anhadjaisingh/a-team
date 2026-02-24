#!/usr/bin/env bash
# TaskCompleted hook — verifies task work was committed before marking complete
# Exit code 0: allow completion
# Exit code 2: send feedback, prevent completion

set -euo pipefail

# Check for uncommitted changes
UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

if [ "$UNCOMMITTED" -gt 0 ]; then
  echo "You have $UNCOMMITTED uncommitted files. Commit your work before marking the task as complete."
  echo ""
  git status --short
  exit 2
fi

# All clear
exit 0
