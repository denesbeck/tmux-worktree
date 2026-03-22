#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

OPEN_CMD="${1:-claude}"

require_git_root
header "Create"

# ── Step 1: Select base branch ──────────────────────────────────
echo -e "${C_BLUE}${C_BOLD}❯ Base branch${C_RESET}"
echo ""

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

BASE_BRANCH=$(git branch --format='%(refname:short)' --sort=-committerdate | \
  fzf \
    --height=10 \
    --layout=reverse \
    --border=rounded \
    --border-label=" branches " \
    --prompt=" " \
    --pointer="▸" \
    --style=minimal \
    --color="$FZF_COLORS" \
    --header="current: ${CURRENT_BRANCH}" \
    --no-info \
    --ansi) || true

if [ -z "$BASE_BRANCH" ]; then
  exit 0
fi

echo -e "${C_DIM}Selected:${C_RESET} ${C_GREEN}${BASE_BRANCH}${C_RESET}"
echo ""

# ── Step 2: Enter new branch name ───────────────────────────────
echo -e "${C_BLUE}${C_BOLD}❯ New branch name${C_RESET}"
echo ""

while true; do
  echo -ne "${C_MAUVE}▸${C_RESET} "
  read -r NEW_BRANCH

  if [ -z "$NEW_BRANCH" ]; then
    exit 0
  fi

  if ! git check-ref-format --branch "$NEW_BRANCH" 2>/dev/null; then
    echo -e "${C_RED}Invalid branch name. Try again.${C_RESET}"
    continue
  fi

  if git show-ref --verify --quiet "refs/heads/$NEW_BRANCH"; then
    echo -e "${C_RED}Branch already exists. Try again.${C_RESET}"
    continue
  fi

  break
done

echo ""

# ── Step 3: Create worktree ─────────────────────────────────────
SAFE_NAME=$(echo "$NEW_BRANCH" | tr '/' '-')
WORKTREE_DIR="${GIT_ROOT}/../wt-${SAFE_NAME}"

echo -e "${C_BLUE}${C_BOLD}❯ Creating worktree${C_RESET}"
echo ""
echo -e "${C_DIM}branch:${C_RESET}    ${C_GREEN}${NEW_BRANCH}${C_RESET}"
echo -e "${C_DIM}base:${C_RESET}      ${C_GREEN}${BASE_BRANCH}${C_RESET}"
echo -e "${C_DIM}directory:${C_RESET} ${C_TEXT}$(basename "$WORKTREE_DIR")/${C_RESET}"
echo ""

if ! git worktree add -b "$NEW_BRANCH" "$WORKTREE_DIR" "$BASE_BRANCH" 2>&1; then
  die "Failed to create worktree."
fi

echo ""
echo -e "${C_GREEN}${C_BOLD}Worktree created!${C_RESET}"
echo ""

# ── Step 4: Open in new tmux window ─────────────────────────────
SESSION=$(tmux display-message -p '#S')
WINDOW_NAME=$(basename "$NEW_BRANCH")
ABS_DIR=$(cd "$WORKTREE_DIR" && pwd)

tmux new-window -t "$SESSION:" -n "$WINDOW_NAME" -c "$ABS_DIR" "$OPEN_CMD"
