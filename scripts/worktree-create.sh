#!/usr/bin/env bash

# ── Theme (Catppuccin Frappé palette) ────────────────────────────
C_BLUE="\033[38;2;140;170;238m"    # #8caaee
C_MAUVE="\033[38;2;202;158;230m"   # #ca9ee6
C_GREEN="\033[38;2;166;209;137m"   # #a6d189
C_RED="\033[38;2;231;130;132m"     # #e78284
C_TEXT="\033[38;2;198;208;245m"    # #c6d0f5
C_DIM="\033[38;2;115;121;148m"     # #737994
C_BOLD="\033[1m"
C_RESET="\033[0m"

die() {
  echo ""
  echo -e "  ${C_RED}${C_BOLD}  Error:${C_RESET}${C_TEXT} $1${C_RESET}"
  echo ""
  echo -e "  ${C_DIM}Press any key to close...${C_RESET}"
  read -rsn1
  exit 1
}

OPEN_CMD="${1:-claude}"

# ── Resolve git root (popup starts in pane's cwd via -d flag) ───

GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || true

if [ -z "$GIT_ROOT" ]; then
  die "Not inside a git repository."
fi

cd "$GIT_ROOT"
REPO_NAME=$(basename "$GIT_ROOT")

# ── Header ───────────────────────────────────────────────────────
clear
echo ""
echo -e "  ${C_MAUVE}${C_BOLD}  Git Worktree${C_RESET}  ${C_DIM}─  ${REPO_NAME}${C_RESET}"
echo ""

# ── Step 1: Select base branch ──────────────────────────────────
echo -e "  ${C_BLUE}${C_BOLD}❯ Base branch${C_RESET}"
echo ""

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

BASE_BRANCH=$(git branch --format='%(refname:short)' --sort=-committerdate | \
  fzf \
    --height=10 \
    --layout=reverse \
    --border=rounded \
    --border-label=" branches " \
    --prompt="  " \
    --pointer="▸" \
    --style=minimal \
    --color="bg+:-1,gutter:-1,current-bg:-1,hl:#ca9ee6,hl+:#ca9ee6,pointer:#e78284,prompt:#8caaee,border:#8caaee,label:#8caaee" \
    --header="  current: ${CURRENT_BRANCH}" \
    --no-info \
    --ansi) || true

if [ -z "$BASE_BRANCH" ]; then
  exit 0
fi

echo -e "  ${C_DIM}Selected:${C_RESET} ${C_GREEN}${BASE_BRANCH}${C_RESET}"
echo ""

# ── Step 2: Enter new branch name ───────────────────────────────
echo -e "  ${C_BLUE}${C_BOLD}❯ New branch name${C_RESET}"
echo ""

while true; do
  echo -ne "  ${C_MAUVE}▸${C_RESET} "
  read -r NEW_BRANCH

  if [ -z "$NEW_BRANCH" ]; then
    exit 0
  fi

  # Validate branch name
  if ! git check-ref-format --branch "$NEW_BRANCH" 2>/dev/null; then
    echo -e "  ${C_RED}  Invalid branch name. Try again.${C_RESET}"
    continue
  fi

  # Check if branch already exists
  if git show-ref --verify --quiet "refs/heads/$NEW_BRANCH"; then
    echo -e "  ${C_RED}  Branch already exists. Try again.${C_RESET}"
    continue
  fi

  break
done

echo ""

# ── Step 3: Create worktree ─────────────────────────────────────
SAFE_NAME=$(echo "$NEW_BRANCH" | tr '/' '-')
WORKTREE_DIR="${GIT_ROOT}/../wt-${SAFE_NAME}"

echo -e "  ${C_BLUE}${C_BOLD}❯ Creating worktree${C_RESET}"
echo ""
echo -e "  ${C_DIM}branch:${C_RESET}    ${C_GREEN}${NEW_BRANCH}${C_RESET}"
echo -e "  ${C_DIM}base:${C_RESET}      ${C_GREEN}${BASE_BRANCH}${C_RESET}"
echo -e "  ${C_DIM}directory:${C_RESET} ${C_TEXT}$(basename "$WORKTREE_DIR")/${C_RESET}"
echo ""

if ! git worktree add -b "$NEW_BRANCH" "$WORKTREE_DIR" "$BASE_BRANCH" 2>&1 | sed "s/^/  /"; then
  die "Failed to create worktree."
fi

echo ""
echo -e "  ${C_GREEN}${C_BOLD}  Worktree created!${C_RESET}"
echo ""

# ── Step 4: Open in new tmux window ─────────────────────────────
SESSION=$(tmux display-message -p '#S')
WINDOW_NAME=$(basename "$NEW_BRANCH")
ABS_DIR=$(cd "$WORKTREE_DIR" && pwd)

tmux new-window -t "$SESSION:" -n "$WINDOW_NAME" -c "$ABS_DIR" "$OPEN_CMD"
