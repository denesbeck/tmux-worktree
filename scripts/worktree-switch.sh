#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

OPEN_CMD="${1:-claude}"

require_git_root
header "Switch"

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

  # Check dirty state
  dirty=""
  if [ -d "$wt_path" ]; then
    changed=$(git -C "$wt_path" status --porcelain 2>/dev/null | head -1)
    if [ -n "$changed" ]; then
      dirty=" *"
    fi
  fi

  # Check if tmux window exists
  win_idx=$(find_tmux_window "$wt_path")
  tmux_icon=""
  if [ -n "$win_idx" ]; then
    tmux_icon="  "
  fi

  WORKTREES+=("${wt_branch}${dirty}${tmux_icon}|${wt_path}|${win_idx}")
done < <(git worktree list)

if [ ${#WORKTREES[@]} -eq 0 ]; then
  echo -e "${C_DIM}No worktrees found (besides main).${C_RESET}"
  echo ""
  echo -e "${C_DIM}Press any key to close...${C_RESET}"
  read -rsn1
  exit 0
fi

# ── fzf picker ───────────────────────────────────────────────────
echo -e "${C_BLUE}${C_BOLD}❯ Select worktree${C_RESET}"
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
    --gutter=" " \
    --style=minimal \
    --color="$FZF_COLORS" \
    --no-info \
    --ansi) || true

if [ -z "$SELECTED" ]; then
  exit 0
fi

# ── Find matching entry and switch ───────────────────────────────
for entry in "${WORKTREES[@]}"; do
  branch="${entry%%|*}"
  if [ "$branch" = "$SELECTED" ]; then
    rest="${entry#*|}"
    wt_path="${rest%%|*}"
    win_idx="${rest##*|}"

    SESSION=$(tmux display-message -p '#S')

    if [ -n "$win_idx" ]; then
      tmux select-window -t "$SESSION:$win_idx"
    else
      WINDOW_NAME=$(basename "$wt_path")
      tmux new-window -t "$SESSION:" -n "$WINDOW_NAME" -c "$wt_path" "$OPEN_CMD"
    fi
    break
  fi
done
