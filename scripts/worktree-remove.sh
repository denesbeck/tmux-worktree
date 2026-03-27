#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# set -e is in common.sh but we need to handle errors manually in the removal flow
source "$SCRIPT_DIR/common.sh"

require_git_root
header "Remove"

# ── Resolve default branch ───────────────────────────────────────
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@') || true
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

# ── Build worktree list ──────────────────────────────────────────
_collect_worktrees() {
  while IFS= read -r line; do
    wt_path=$(echo "$line" | awk '{print $1}')
    wt_branch=$(echo "$line" | sed 's/.*\[\(.*\)\].*/\1/')
    wt_bare=$(echo "$line" | grep -c "(bare)" || true)

    if [ "$wt_bare" -gt 0 ] || [ "$wt_path" = "$GIT_ROOT" ] || [ "$wt_branch" = "$DEFAULT_BRANCH" ]; then
      continue
    fi

    echo "${wt_branch}|${wt_path}"
  done < <(git worktree list)
}
export -f _collect_worktrees
export GIT_ROOT DEFAULT_BRANCH
spin_capture WORKTREE_RAW "Loading worktrees..." bash -c "_collect_worktrees"

WORKTREES=()
while IFS= read -r entry; do
  [ -n "$entry" ] && WORKTREES+=("$entry")
done <<< "$WORKTREE_RAW"

if [ ${#WORKTREES[@]} -eq 0 ]; then
  echo -e "${C_DIM}No worktrees found (besides main).${C_RESET}"
  echo ""
  echo -e "${C_DIM}Press any key to close...${C_RESET}"
  read -rsn1
  exit 0
fi

# ── fzf picker ───────────────────────────────────────────────────
echo -e "${C_BLUE}${C_BOLD}❯ Select worktrees to remove (Tab to multi-select)${C_RESET}"
echo ""

DISPLAY_LIST=""
for entry in "${WORKTREES[@]}"; do
  branch="${entry%%|*}"
  DISPLAY_LIST+="${branch}"$'\n'
done

SELECTED=$(echo "$DISPLAY_LIST" | sed '/^$/d' |
  fzf \
    --multi \
    --height=12 \
    --layout=reverse \
    --border=rounded \
    --border-label=" worktrees " \
    --prompt=" " \
    --pointer="" \
    --marker="● " \
    --gutter=" " \
    --style=minimal \
    --color="$FZF_COLORS" \
    --no-info \
    --ansi) || true

if [ -z "$SELECTED" ]; then
  exit 0
fi

# ── Find matching entries ────────────────────────────────────────
declare -a TARGETS
while IFS= read -r selected_branch; do
  TARGET_PATH=""
  TARGET_BRANCH=""
  for entry in "${WORKTREES[@]}"; do
    branch="${entry%%|*}"
    path="${entry##*|}"
    if [ "$branch" = "$selected_branch" ]; then
      TARGET_PATH="$path"
      TARGET_BRANCH="$branch"
      break
    fi
  done

  if [ -z "$TARGET_PATH" ]; then
    echo -e "${C_YELLOW}Warning: Could not find worktree for ${selected_branch}.${C_RESET}"
    continue
  fi

  # Protect default branch (safety net)
  if [ "$TARGET_BRANCH" = "$DEFAULT_BRANCH" ]; then
    echo -e "${C_YELLOW}Warning: Cannot remove the default branch (${DEFAULT_BRANCH}).${C_RESET}"
    continue
  fi

  TARGETS+=("${TARGET_BRANCH}|${TARGET_PATH}")
done <<<"$SELECTED"

if [ ${#TARGETS[@]} -eq 0 ]; then
  echo -e "${C_DIM}No valid worktrees to remove.${C_RESET}"
  exit 0
fi

# ── Confirm ──────────────────────────────────────────────────────
echo ""
echo -e "${C_YELLOW}${C_BOLD}Warning:${C_RESET} This will remove:"
echo ""

# Check for uncommitted changes and display summary
declare -a DIRTY_TARGETS
for target in "${TARGETS[@]}"; do
  branch="${target%%|*}"
  path="${target##*|}"
  echo -e "${C_DIM}• ${C_RESET}${C_RED}${branch}${C_RESET} ${C_DIM}($(basename "$path")/)"

  if [ -d "$path" ]; then
    changed=$(git -C "$path" status --porcelain 2>/dev/null | head -1)
    if [ -n "$changed" ]; then
      DIRTY_TARGETS+=("$target")
      echo -e "  ${C_RED}└─ has uncommitted changes${C_RESET}"
    fi
  fi
done
echo ""

if [ ${#DIRTY_TARGETS[@]} -gt 0 ]; then
  echo -e "${C_RED}${C_BOLD}${#DIRTY_TARGETS[@]} worktree(s) have uncommitted changes!${C_RESET}"
  echo ""
  echo -ne "${C_MAUVE}▸${C_RESET} Force remove with uncommitted changes? [y/N] "
else
  echo -ne "${C_MAUVE}▸${C_RESET} Confirm? [y/N] "
fi
read -rsn1 CONFIRM
echo ""

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  echo ""
  echo -e "${C_DIM}Cancelled.${C_RESET}"
  sleep 0.5
  exit 0
fi

echo ""

# ── Switch to main worktree before destructive operations ────────
MAIN_WT_PATH=$(git worktree list | head -1 | awk '{print $1}')
cd "$MAIN_WT_PATH"

# ── Remove all worktrees ─────────────────────────────────────────
SESSION=$(tmux display-message -p '#S')
for target in "${TARGETS[@]}"; do
  TARGET_BRANCH="${target%%|*}"
  TARGET_PATH="${target##*|}"

  # Close tmux window if open
  win_idx=$(find_tmux_window "$TARGET_PATH")
  if [ -n "$win_idx" ]; then
    tmux kill-window -t "$SESSION:$win_idx" 2>/dev/null || true
  fi

  # Determine if this target is dirty
  IS_DIRTY=false
  if [ -d "$TARGET_PATH" ]; then
    changed=$(git -C "$TARGET_PATH" status --porcelain 2>/dev/null | head -1)
    if [ -n "$changed" ]; then
      IS_DIRTY=true
    fi
  fi

  # Remove worktree
  if [ "$IS_DIRTY" = true ]; then
    if ! spin "Removing ${TARGET_BRANCH}..." git worktree remove "$TARGET_PATH" --force; then
      echo -e "${C_YELLOW}Warning: Failed to remove worktree ${TARGET_BRANCH}.${C_RESET}"
      continue
    fi
  else
    if ! spin "Removing ${TARGET_BRANCH}..." git worktree remove "$TARGET_PATH"; then
      echo -e "${C_YELLOW}Warning: Failed to remove worktree ${TARGET_BRANCH}.${C_RESET}"
      continue
    fi
  fi

  # Delete branch
  if git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
    if ! git branch -d "$TARGET_BRANCH" 2>&1; then
      echo -ne "${C_MAUVE}▸${C_RESET} Force delete branch ${TARGET_BRANCH}? [y/N] "
      read -rsn1 FORCE_DEL
      echo ""
      if [ "$FORCE_DEL" = "y" ] || [ "$FORCE_DEL" = "Y" ]; then
        git branch -D "$TARGET_BRANCH" 2>&1
      else
        echo -e "${C_DIM}Branch kept: ${TARGET_BRANCH}${C_RESET}"
      fi
    fi
  fi
done

echo ""
echo -e "${C_GREEN}${C_BOLD}Removed ${#TARGETS[@]} worktree(s)!${C_RESET}"
echo ""
echo -e "${C_DIM}Press Enter to close...${C_RESET}"
read -r
