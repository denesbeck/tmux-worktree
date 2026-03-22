#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# User-configurable options with defaults
get_opt() {
  local val
  val=$(tmux show-option -gqv "$1")
  echo "${val:-$2}"
}

worktree_create_key=$(get_opt @worktree_create_key "W")
worktree_switch_key=$(get_opt @worktree_switch_key "w")
worktree_remove_key=$(get_opt @worktree_remove_key "X")
worktree_open_cmds=$(get_opt @worktree_open_cmds "claude,gemini,aider,codex,opencode,\$SHELL")
worktree_popup_width=$(get_opt @worktree_popup_width "60%")
worktree_popup_height=$(get_opt @worktree_popup_height "40%")

# prefix + W  →  Create worktree
tmux bind-key "$worktree_create_key" display-popup \
  -d '#{pane_current_path}' \
  -w "$worktree_popup_width" \
  -h "$worktree_popup_height" \
  -E \
  "bash '$CURRENT_DIR/scripts/worktree-create.sh' '$worktree_open_cmds'"

# prefix + w  →  Switch to worktree
tmux bind-key "$worktree_switch_key" display-popup \
  -d '#{pane_current_path}' \
  -w "$worktree_popup_width" \
  -h "$worktree_popup_height" \
  -E \
  "bash '$CURRENT_DIR/scripts/worktree-switch.sh' '$worktree_open_cmds'"

# prefix + X  →  Remove worktree
tmux bind-key "$worktree_remove_key" display-popup \
  -d '#{pane_current_path}' \
  -w "$worktree_popup_width" \
  -h "$worktree_popup_height" \
  -E \
  "bash '$CURRENT_DIR/scripts/worktree-remove.sh'"
