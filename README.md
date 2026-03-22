# tmux-worktree

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A tmux plugin for managing git worktrees. Create, switch, and remove worktrees from a floating popup — each worktree opens in its own tmux window.

## Overview

tmux-worktree provides a terminal UI for git worktree management directly inside tmux. It uses `fzf` for interactive branch selection and `tmux display-popup` for a floating window experience.

**Key Features:**
- Create worktrees with interactive base branch selection
- AI tool picker — choose between Claude Code, Gemini CLI, Aider, Codex CLI, OpenCode, or a plain shell when opening a worktree (only installed tools are shown as selectable)
- Switch between existing worktrees (opens or focuses tmux window)
- Remove worktrees with confirmation and cleanup (directory, branch, tmux window)
- Safe removal — conditional force for dirty worktrees, safe branch deletion with fallback prompt
- Dirty state and active window indicators
- Default branch and main worktree protection on removal
- Fully configurable keybindings, popup dimensions, and tool list

## Prerequisites

- tmux 3.2+ (for `display-popup` support)
- [fzf](https://github.com/junegunn/fzf)
- git

## Installation

### With [TPM](https://github.com/tmux-plugins/tpm)

Add to your `tmux.conf`:

```bash
set -g @plugin 'denesbeck/tmux-worktree'
```

Then press `prefix + I` to install.

### Manual

Clone the repository:

```bash
git clone https://github.com/denesbeck/tmux-worktree.git ~/.tmux/plugins/tmux-worktree
```

Add to your `tmux.conf`:

```bash
run ~/.tmux/plugins/tmux-worktree/worktree.tmux
```

Reload tmux:

```bash
tmux source ~/.config/tmux/tmux.conf
```

## Usage

| Keybinding   | Action | Description                                                    |
|--------------|--------|----------------------------------------------------------------|
| `prefix + W` | Create | Select base branch, name new branch, create worktree + window |
| `prefix + w` | Switch | Pick from existing worktrees, jump to or open tmux window      |
| `prefix + X` | Remove | Pick worktree to delete, cleans up directory + branch + window |

### Create workflow

1. Press `prefix + W`
2. Select a base branch from the fzf picker
3. Enter a new branch name
4. Select a tool to open with (skipped if only one is available)
5. Worktree is created and a new tmux window opens with the selected tool

### Switch workflow

1. Press `prefix + w`
2. Select a worktree from the list (`*` = dirty, window icon = tmux window open)
3. Jumps to existing window, or select a tool and open a new one

### Remove workflow

1. Press `prefix + X`
2. Select a worktree to remove
3. Confirm deletion (explicit force-remove prompt if worktree has uncommitted changes)
4. Worktree directory and tmux window are cleaned up
5. Branch is deleted with safe delete; if unmerged, prompts for force delete or keeps it

## Configuration

All options are set in `tmux.conf`:

```bash
# Keybindings (defaults shown)
set -g @worktree_create_key 'W'
set -g @worktree_switch_key 'w'
set -g @worktree_remove_key 'X'

# Comma-separated list of tools to offer when opening a worktree
# (default: claude,gemini,aider,codex,opencode,$SHELL)
# Only installed tools appear as selectable; others are shown dimmed
set -g @worktree_open_cmds 'claude,gemini,aider,codex,opencode,$SHELL'

# Popup dimensions (default: 60% x 40%)
set -g @worktree_popup_width '60%'
set -g @worktree_popup_height '40%'
```

## Project Structure

```
tmux-worktree/
├── worktree.tmux          # Plugin entry point, keybindings
└── scripts/
    ├── common.sh           # Shared theme, helpers, fzf config
    ├── worktree-create.sh  # Create worktree flow
    ├── worktree-switch.sh  # Switch/open worktree flow
    └── worktree-remove.sh  # Remove worktree flow
```

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
