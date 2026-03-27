#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
  echo -ne "${C_MAUVE}${C_RESET} "
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
    SELECTED=$(echo "$IGNORED_FILES" |
      fzf \
        --multi \
        --height=12 \
        --layout=reverse \
        --border=rounded \
        --border-label=" ignored files " \
        --prompt=" " \
        --pointer="" \
        --marker="● " \
        --gutter=" " \
        --style=minimal \
        --color="$FZF_COLORS" \
        --header="Tab: select · Enter: confirm · Esc: cancel" \
        --no-info \
        --ansi) || true

    if [ -z "$SELECTED" ]; then
      exit 0
    fi

    echo ""
    echo -ne "${C_BLUE}${C_BOLD}❯${C_RESET} ${C_TEXT}(s)ymlink or (c)opy?${C_RESET} ${C_DIM}[s/c]:${C_RESET} "
    read -rsn1 MODE_CHOICE
    echo ""

    MODE="symlink"
    if [ "$MODE_CHOICE" = "c" ] || [ "$MODE_CHOICE" = "C" ]; then
      MODE="copy"
    fi

    echo -e "${C_DIM}Selected:${C_RESET} ${C_GREEN}${MODE}${C_RESET}"
    echo ""

    # Save config
    CONFIG_DIR=$(dirname "$REPO_CONFIG")
    mkdir -p "$CONFIG_DIR"
    while IFS= read -r file; do
      echo "${MODE}:${file}"
    done <<<"$SELECTED" >"$REPO_CONFIG"

    SYNC_CONFIG_FILE="$REPO_CONFIG"
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
