#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

require_git_root
header "Remove"

# ── Build worktree list ──────────────────────────────────────────
WORKTREES=()
while IFS= read -r line; do
  wt_path=$(echo "$line" | awk '{print $1}')
  wt_branch=$(echo "$line" | sed 's/.*\[\(.*\)\].*/\1/')
  wt_bare=$(echo "$line" | grep -c "(bare)")

  # Skip bare repos and the main worktree
  if [ "$wt_bare" -gt 0 ] || [ "$wt_path" = "$GIT_ROOT" ]; then
    continue
  fi

  WORKTREES+=("${wt_branch}|${wt_path}")
done < <(git worktree list)

if [ ${#WORKTREES[@]} -eq 0 ]; then
  echo -e "${C_DIM}No worktrees found (besides main).${C_RESET}"
  echo ""
  echo -e "${C_DIM}Press any key to close...${C_RESET}"
  read -rsn1
  exit 0
fi

# ── fzf picker ───────────────────────────────────────────────────
echo -e "${C_BLUE}${C_BOLD}❯ Select worktree to remove${C_RESET}"
echo ""

DISPLAY_LIST=""
for entry in "${WORKTREES[@]}"; do
  branch="${entry%%|*}"
  DISPLAY_LIST+="${branch}"$'\n'
done

SELECTED=$(echo "$DISPLAY_LIST" | sed '/^$/d' | \
  fzf \
    --height=12 \
    --layout=reverse \
    --border=rounded \
    --border-label=" worktrees " \
    --prompt=" " \
    --pointer="▸" \
    --style=minimal \
    --color="$FZF_COLORS" \
    --no-info \
    --ansi) || true

if [ -z "$SELECTED" ]; then
  exit 0
fi

# ── Find matching entry ──────────────────────────────────────────
TARGET_PATH=""
TARGET_BRANCH=""
for entry in "${WORKTREES[@]}"; do
  branch="${entry%%|*}"
  path="${entry##*|}"
  if [ "$branch" = "$SELECTED" ]; then
    TARGET_PATH="$path"
    TARGET_BRANCH="$branch"
    break
  fi
done

if [ -z "$TARGET_PATH" ]; then
  die "Could not find worktree."
fi

# Protect default branch
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@') || true
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
if [ "$TARGET_BRANCH" = "$DEFAULT_BRANCH" ]; then
  die "Cannot remove the default branch (${DEFAULT_BRANCH})."
fi

# ── Confirm ──────────────────────────────────────────────────────
echo ""
echo -e "${C_YELLOW}${C_BOLD}Warning:${C_RESET} This will remove:"
echo ""
echo -e "${C_DIM}branch:${C_RESET}    ${C_RED}${TARGET_BRANCH}${C_RESET}"
echo -e "${C_DIM}directory:${C_RESET} ${C_RED}$(basename "$TARGET_PATH")/${C_RESET}"
echo ""

# Check for uncommitted changes
if [ -d "$TARGET_PATH" ]; then
  changed=$(git -C "$TARGET_PATH" status --porcelain 2>/dev/null | head -1)
  if [ -n "$changed" ]; then
    echo -e "${C_RED}${C_BOLD}This worktree has uncommitted changes!${C_RESET}"
    echo ""
  fi
fi

echo -ne "${C_MAUVE}▸${C_RESET} Confirm? [y/N] "
read -rsn1 CONFIRM
echo ""

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  echo ""
  echo -e "${C_DIM}Cancelled.${C_RESET}"
  sleep 0.5
  exit 0
fi

echo ""

# ── Close tmux window if open ────────────────────────────────────
SESSION=$(tmux display-message -p '#S')
win_idx=$(find_tmux_window "$TARGET_PATH")
if [ -n "$win_idx" ]; then
  tmux kill-window -t "$SESSION:$win_idx" 2>/dev/null || true
  echo -e "${C_DIM}Closed tmux window.${C_RESET}"
fi

# ── Remove worktree ──────────────────────────────────────────────
if ! git worktree remove "$TARGET_PATH" --force 2>&1; then
  die "Failed to remove worktree."
fi

# ── Delete branch ────────────────────────────────────────────────
if git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
  git branch -D "$TARGET_BRANCH" 2>&1
fi

echo ""
echo -e "${C_GREEN}${C_BOLD}Removed!${C_RESET}"
echo ""
echo -e "${C_DIM}Press Enter to close...${C_RESET}"
read -r
