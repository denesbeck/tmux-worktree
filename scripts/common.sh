# ── Theme (Catppuccin Frappé palette) ────────────────────────────
C_BLUE="\033[38;2;140;170;238m"    # #8caaee
C_MAUVE="\033[38;2;202;158;230m"   # #ca9ee6
C_GREEN="\033[38;2;166;209;137m"   # #a6d189
C_RED="\033[38;2;231;130;132m"     # #e78284
C_YELLOW="\033[38;2;229;200;144m"  # #e5c890
C_TEXT="\033[38;2;198;208;245m"    # #c6d0f5
C_DIM="\033[38;2;115;121;148m"     # #737994
C_BOLD="\033[1m"
C_RESET="\033[0m"

FZF_COLORS="bg+:-1,gutter:-1,current-bg:-1,hl:#ca9ee6,hl+:#ca9ee6,pointer:#e78284,prompt:#8caaee,border:#8caaee,label:#8caaee"

die() {
  echo ""
  echo -e "${C_RED}${C_BOLD}Error:${C_RESET}${C_TEXT} $1${C_RESET}"
  echo ""
  echo -e "${C_DIM}Press any key to close...${C_RESET}"
  read -rsn1
  exit 1
}

require_git_root() {
  GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || true
  if [ -z "$GIT_ROOT" ]; then
    die "Not inside a git repository."
  fi
  cd "$GIT_ROOT"
  REPO_NAME=$(basename "$GIT_ROOT")
}

header() {
  clear
  echo ""
  echo -e "${C_MAUVE}${C_BOLD}Git Worktree${C_RESET} ${C_DIM}─ ${REPO_NAME} ─ $1${C_RESET}"
  echo ""
}

# Find tmux window name for a given worktree path
find_tmux_window() {
  local wt_path="$1"
  local session
  session=$(tmux display-message -p '#S')
  tmux list-windows -t "$session" -F '#{window_index} #{window_name} #{pane_current_path}' 2>/dev/null | \
    while read -r idx name path; do
      if [ "$path" = "$wt_path" ]; then
        echo "$idx"
        return
      fi
    done
}
