#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

OPEN_CMDS="${1:-claude,gemini,aider,codex,opencode,\$SHELL}"

require_git_root
header "Create"

# ── Step 1: Select base branch ──────────────────────────────────
echo -e "${C_BLUE}${C_BOLD}❯ Base branch${C_RESET}"
echo ""

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

BASE_BRANCH=$(git branch --format='%(refname:short)' --sort=-committerdate |
  fzf \
    --height=10 \
    --layout=reverse \
    --border=rounded \
    --border-label=" branches " \
    --prompt=" " \
    --pointer="" \
    --gutter=" " \
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
  echo -ne "${C_MAUVE}${C_RESET} "
  read -r NEW_BRANCH

  if [ -z "$NEW_BRANCH" ]; then
    exit 0
  fi

  if ! git check-ref-format --branch "$NEW_BRANCH" >/dev/null 2>&1; then
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

# ── Step 3: Sync ignored files ────────────────────────────────
REPO_CONFIG=$(get_repo_config_path)
SYNC_CHOICE=""

echo -e "${C_BLUE}${C_BOLD}❯ Sync ignored files${C_RESET}"
echo ""

if [ -f "$REPO_CONFIG" ]; then
  SYNC_OPTIONS=$(printf "Load existing config\nCreate new config\nSkip")
  DEFAULT_POS="1"
else
  SYNC_OPTIONS=$(printf "Create new config\nSkip")
  DEFAULT_POS="1"
fi

SYNC_CHOICE=$(echo "$SYNC_OPTIONS" |
  fzf \
    --height=7 \
    --layout=reverse \
    --border=rounded \
    --border-label=" sync " \
    --prompt=" " \
    --pointer="" \
    --gutter=" " \
    --style=minimal \
    --color="$FZF_COLORS" \
    --header="Enter: confirm · Esc: cancel" \
    --no-info \
    --ansi \
    --bind "start:pos($DEFAULT_POS)") || true

if [ -z "$SYNC_CHOICE" ]; then
  exit 0
fi

# ── Step 3b: Configure sync (if creating new config) ─────────
SYNC_CONFIG_FILE=""

if [ "$SYNC_CHOICE" = "Create new config" ]; then
  spin_capture IGNORED_FILES "Scanning ignored files..." bash -c "git status --ignored --porcelain 2>/dev/null | grep '^!! ' | sed 's/^!! //' | sed 's:\/$::'"

  if [ -n "$IGNORED_FILES" ]; then
    # Create temp files for per-file mode selection
    STATE_FILE=$(mktemp)
    SYNC_HELPER=$(mktemp)
    cleanup_sync() { rm -f "$STATE_FILE" "${STATE_FILE}.tmp" "$SYNC_HELPER"; }
    trap cleanup_sync EXIT

    # Initialize state (all skip)
    while IFS= read -r file; do
      printf '·\t%s\n' "$file"
    done <<<"$IGNORED_FILES" >"$STATE_FILE"

    # Helper for toggle/render (avoids escaping issues in fzf --bind)
    cat >"$SYNC_HELPER" <<'HELPEREOF'
#!/usr/bin/env bash
ACTION="$1"; SF="$2"
if [ "$ACTION" = "render" ]; then
  awk -F'\t' '{
    if($1=="S") printf "\033[38;2;166;209;137m● symlink\033[0m\t%s\n", $2
    else if($1=="C") printf "\033[38;2;140;170;238m● copy   \033[0m\t%s\n", $2
    else printf "\033[38;2;115;121;148m○ skip   \033[0m\t%s\n", $2
  }' "$SF"
elif [ "$ACTION" = "toggle" ]; then
  awk -F'\t' -v p="$4" -v m="$3" 'BEGIN{OFS="\t"} $2==p{$1=m} 1' "$SF" > "${SF}.tmp" && mv "${SF}.tmp" "$SF"
fi
HELPEREOF
    chmod +x "$SYNC_HELPER"

    "$SYNC_HELPER" render "$STATE_FILE" |
      fzf \
        --height=12 \
        --layout=reverse \
        --border=rounded \
        --border-label=" ignored files " \
        --prompt=" " \
        --pointer="" \
        --gutter=" " \
        --style=minimal \
        --no-sort \
        --disabled \
        --color="$FZF_COLORS" \
        --header="s: symlink · c: copy · d: skip · Enter: confirm · Esc: cancel" \
        --no-info \
        --ansi \
        --delimiter=$'\t' \
        --bind "s:execute-silent('$SYNC_HELPER' toggle '$STATE_FILE' S '{2}')+reload('$SYNC_HELPER' render '$STATE_FILE')" \
        --bind "c:execute-silent('$SYNC_HELPER' toggle '$STATE_FILE' C '{2}')+reload('$SYNC_HELPER' render '$STATE_FILE')" \
        --bind "d:execute-silent('$SYNC_HELPER' toggle '$STATE_FILE' · '{2}')+reload('$SYNC_HELPER' render '$STATE_FILE')" \
        --bind "enter:accept" \
        >/dev/null 2>&1 || {
      cleanup_sync
      exit 0
    }

    # Check if any files were marked
    if grep -q '^[SC]' "$STATE_FILE"; then
      S_COUNT=$(grep -c '^S' "$STATE_FILE" 2>/dev/null || echo "0")
      C_COUNT=$(grep -c '^C' "$STATE_FILE" 2>/dev/null || echo "0")
      SUMMARY=""
      [ "$S_COUNT" -gt 0 ] && SUMMARY="${S_COUNT} symlink"
      [ "$C_COUNT" -gt 0 ] && {
        [ -n "$SUMMARY" ] && SUMMARY="${SUMMARY}, "
        SUMMARY="${SUMMARY}${C_COUNT} copy"
      }
      echo -e "${C_DIM}Selected:${C_RESET} ${C_GREEN}${SUMMARY}${C_RESET}"
      echo ""

      # Save config
      CONFIG_DIR=$(dirname "$REPO_CONFIG")
      mkdir -p "$CONFIG_DIR"
      awk -F'\t' '$1=="S"{printf "symlink:%s\n",$2} $1=="C"{printf "copy:%s\n",$2}' "$STATE_FILE" >"$REPO_CONFIG"

      cleanup_sync
      SYNC_CONFIG_FILE="$REPO_CONFIG"
    else
      cleanup_sync
      echo -e "${C_DIM}Selected:${C_RESET} ${C_GREEN}none${C_RESET}"
      echo ""
    fi
  else
    echo -e "${C_DIM}No ignored files found.${C_RESET}"
    echo ""
  fi
elif [ "$SYNC_CHOICE" = "Load existing config" ]; then
  SYNC_CONFIG_FILE="$REPO_CONFIG"
fi

# ── Step 4: Select tool ──────────────────────────────────────────
OPEN_CMD=$(pick_open_cmd "$OPEN_CMDS") || exit 0

echo -e "${C_DIM}Selected:${C_RESET} ${C_GREEN}${OPEN_CMD}${C_RESET}"
echo ""

# ── Step 5: Create worktree ─────────────────────────────────────
SAFE_NAME=$(echo "$NEW_BRANCH" | tr '/' '-')
WORKTREE_DIR="${GIT_ROOT}/../wt-${SAFE_NAME}"

echo -e "${C_BLUE}${C_BOLD}❯ Creating worktree${C_RESET}"
echo ""
echo -e "${C_DIM}branch:${C_RESET}    ${C_GREEN}${NEW_BRANCH}${C_RESET}"
echo -e "${C_DIM}base:${C_RESET}      ${C_GREEN}${BASE_BRANCH}${C_RESET}"
echo -e "${C_DIM}directory:${C_RESET} ${C_TEXT}$(basename "$WORKTREE_DIR")/${C_RESET}"
echo ""

if ! spin "Creating worktree..." git worktree add -b "$NEW_BRANCH" "$WORKTREE_DIR" "$BASE_BRANCH"; then
  die "Failed to create worktree."
fi

echo -e "${C_GREEN}${C_BOLD}Worktree created!${C_RESET}"
echo ""

# ── Step 6: Apply ignored files sync ─────────────────────────────
ABS_WORKTREE=$(cd "$WORKTREE_DIR" && pwd)

if [ -n "$SYNC_CONFIG_FILE" ] && [ -f "$SYNC_CONFIG_FILE" ]; then
  apply_sync_config "$GIT_ROOT" "$ABS_WORKTREE" "$SYNC_CONFIG_FILE"
  echo ""
fi

# ── Step 7: Open in new tmux window ─────────────────────────────
SESSION=$(tmux display-message -p '#S')
WINDOW_NAME=$(basename "$NEW_BRANCH")

tmux new-window -t "$SESSION:" -n "$WINDOW_NAME" -c "$ABS_WORKTREE" "$OPEN_CMD"
