#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# User-configurable options with defaults
default_key="W"
worktree_key=$(tmux show-option -gqv @worktree_key)
worktree_key=${worktree_key:-$default_key}

default_open_cmd="claude"
worktree_open_cmd=$(tmux show-option -gqv @worktree_open_cmd)
worktree_open_cmd=${worktree_open_cmd:-$default_open_cmd}

default_popup_width="60%"
worktree_popup_width=$(tmux show-option -gqv @worktree_popup_width)
worktree_popup_width=${worktree_popup_width:-$default_popup_width}

default_popup_height="40%"
worktree_popup_height=$(tmux show-option -gqv @worktree_popup_height)
worktree_popup_height=${worktree_popup_height:-$default_popup_height}

# Bind key to open the worktree creator popup
tmux bind-key "$worktree_key" display-popup \
  -d '#{pane_current_path}' \
  -w "$worktree_popup_width" \
  -h "$worktree_popup_height" \
  -E \
  "bash $CURRENT_DIR/scripts/worktree-create.sh $worktree_open_cmd"
