set -eo pipefail

# ── Dependency checks ────────────────────────────────────────────
for cmd in git fzf tmux; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: '$cmd' is required but not installed." >&2
    exit 1
  fi
done

# ── Theme (Catppuccin Frappé palette) ────────────────────────────
C_BLUE="\033[38;2;140;170;238m"   # #8caaee
C_MAUVE="\033[38;2;202;158;230m"  # #ca9ee6
C_GREEN="\033[38;2;166;209;137m"  # #a6d189
C_RED="\033[38;2;231;130;132m"    # #e78284
C_YELLOW="\033[38;2;229;200;144m" # #e5c890
C_TEXT="\033[38;2;198;208;245m"   # #c6d0f5
C_DIM="\033[38;2;115;121;148m"    # #737994
C_BOLD="\033[1m"
C_RESET="\033[0m"

FZF_COLORS="bg:-1,fg:-1,bg+:-1,fg+:-1,gutter:-1,current-bg:-1,selected-bg:-1,list-bg:-1,input-bg:-1,header-bg:-1,hl:#ca9ee6,hl+:#ca9ee6,pointer:#e78284,prompt:#8caaee,border:#8caaee,label:#8caaee"

# Run a command with a spinner animation
# Usage: spin "message" command [args...]
spin() {
  local msg="$1"
  shift
  local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  local i=0

  "$@" >/dev/null 2>&1 &
  local pid=$!

  tput civis 2>/dev/null || true  # hide cursor
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r${C_MAUVE}%s${C_RESET} ${C_DIM}%s${C_RESET}" "${frames[$i]}" "$msg"
    i=$(( (i + 1) % ${#frames[@]} ))
    sleep 0.08
  done

  wait "$pid"
  local exit_code=$?
  printf "\r\033[K"  # clear spinner line
  tput cnorm 2>/dev/null || true  # restore cursor
  return $exit_code
}

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

# Labels for known CLI tools
tool_label() {
  case "$1" in
    claude) echo "Claude Code  (Anthropic)" ;;
    gemini) echo "Gemini CLI   (Google)" ;;
    aider) echo "Aider        (Open Source)" ;;
    codex) echo "Codex CLI    (OpenAI)" ;;
    opencode) echo "OpenCode     (Open Source)" ;;
    '$SHELL' | "\$SHELL") echo "Shell        ($SHELL)" ;;
    *) echo "$1" ;;
  esac
}

# Pick an open command from the comma-separated list
# Usage: OPEN_CMD=$(pick_open_cmd "$comma_list")
pick_open_cmd() {
  local cmds_csv="$1"
  local -a all_cmds=()
  local -a labels=()
  local -a is_available=()
  local available_count=0

  IFS=',' read -ra all_cmds <<<"$cmds_csv"

  # Resolve and check availability for each command
  for i in "${!all_cmds[@]}"; do
    local cmd
    cmd=$(echo "${all_cmds[$i]}" | xargs) # trim whitespace
    all_cmds[$i]="$cmd"

    if [ "$cmd" = '$SHELL' ] || [ "$cmd" = "\$SHELL" ]; then
      all_cmds[$i]='$SHELL'
      is_available+=("1")
      ((available_count++)) || true
    elif command -v "$cmd" &>/dev/null; then
      is_available+=("1")
      ((available_count++)) || true
    else
      is_available+=("0")
    fi
  done

  if [ "$available_count" -eq 0 ]; then
    echo "$SHELL"
    return
  fi

  # Single available option — skip picker
  if [ "$available_count" -eq 1 ]; then
    for i in "${!all_cmds[@]}"; do
      if [ "${is_available[$i]}" = "1" ]; then
        local single="${all_cmds[$i]}"
        if [ "$single" = '$SHELL' ]; then
          echo "$SHELL"
        else
          echo "$single"
        fi
        return
      fi
    done
  fi

  # Build sorted display list — available first, then dimmed unavailable
  local -a sorted_cmds=()
  local -a sorted_available=()

  for i in "${!all_cmds[@]}"; do
    if [ "${is_available[$i]}" = "1" ]; then
      sorted_cmds+=("${all_cmds[$i]}")
      sorted_available+=("1")
    fi
  done
  for i in "${!all_cmds[@]}"; do
    if [ "${is_available[$i]}" = "0" ]; then
      sorted_cmds+=("${all_cmds[$i]}")
      sorted_available+=("0")
    fi
  done

  all_cmds=("${sorted_cmds[@]}")
  is_available=("${sorted_available[@]}")

  for i in "${!all_cmds[@]}"; do
    local label
    label=$(tool_label "${all_cmds[$i]}")
    if [ "${is_available[$i]}" = "0" ]; then
      labels+=("${C_DIM}${label}  (not installed)${C_RESET}")
    else
      labels+=("$label")
    fi
  done

  echo -e "${C_BLUE}${C_BOLD}❯ Open with${C_RESET}" >&2
  echo "" >&2

  local selected
  selected=$(printf '%b\n' "${labels[@]}" |
    fzf \
      --height=$((${#labels[@]} + 4)) \
      --layout=reverse \
      --border=rounded \
      --border-label=" tools " \
      --prompt=" " \
      --pointer="" \
      --gutter=" " \
      --style=minimal \
      --color="$FZF_COLORS" \
      --no-info \
      --ansi) || true

  if [ -z "$selected" ]; then
    return 1
  fi

  # Check if user selected a disabled item
  if echo "$selected" | grep -q "(not installed)"; then
    local tool_name
    tool_name=$(echo "$selected" | sed 's/ *(not installed).*//' | xargs)
    echo -e "${C_RED}${tool_name} is not installed.${C_RESET}" >&2
    return 1
  fi

  # Map label back to command
  for i in "${!labels[@]}"; do
    if [ "${is_available[$i]}" = "1" ] && [ "${labels[$i]}" = "$selected" ]; then
      local picked="${all_cmds[$i]}"
      if [ "$picked" = '$SHELL' ]; then
        echo "$SHELL"
      else
        echo "$picked"
      fi
      return
    fi
  done

  echo "$SHELL"
}

# Get config file path for current repo (uses XDG_CONFIG_HOME)
get_repo_config_path() {
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-worktree"
  local repo_hash
  repo_hash=$(printf '%s' "$GIT_ROOT" | md5 2>/dev/null || printf '%s' "$GIT_ROOT" | md5sum | cut -d' ' -f1)
  echo "${config_dir}/${REPO_NAME}-${repo_hash:0:8}.conf"
}

# Apply sync config: symlink/copy ignored files to worktree
apply_sync_config() {
  local src_root="$1"
  local dest_root="$2"
  local config_file="$3"
  local count=0

  while IFS=: read -r mode path; do
    [ -z "$mode" ] || [ -z "$path" ] && continue
    [[ "$mode" == \#* ]] && continue

    local src="${src_root}/${path}"
    local dest="${dest_root}/${path}"

    if [ ! -e "$src" ]; then
      echo -e "  ${C_DIM}skip:${C_RESET}    ${C_YELLOW}${path}${C_RESET} ${C_DIM}(not found)${C_RESET}"
      continue
    fi

    mkdir -p "$(dirname "$dest")"

    if [ "$mode" = "symlink" ]; then
      ln -sfn "$src" "$dest"
      echo -e "  ${C_DIM}symlink:${C_RESET} ${C_GREEN}${path}${C_RESET}"
    elif [ "$mode" = "copy" ]; then
      cp -a "$src" "$dest"
      echo -e "  ${C_DIM}copy:${C_RESET}    ${C_GREEN}${path}${C_RESET}"
    fi
    ((count++)) || true
  done <"$config_file"

  echo ""
  echo -e "${C_DIM}${count} file(s) synced.${C_RESET}"
}

# Find tmux window name for a given worktree path
find_tmux_window() {
  local wt_path="$1"
  local session
  session=$(tmux display-message -p '#S')
  tmux list-windows -t "$session" -F '#{window_index} #{window_name} #{pane_current_path}' 2>/dev/null |
    while read -r idx name path; do
      if [ "$path" = "$wt_path" ]; then
        echo "$idx"
        return
      fi
    done
}
