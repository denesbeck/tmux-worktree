# tmux-worktree

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A tmux plugin for managing git worktrees. Create, switch, and remove worktrees from a floating popup — each worktree opens in its own tmux window.

![tmux-worktree-create](https://github.com/user-attachments/assets/94ea2ce9-ddc3-47bc-93d2-0edd1875d36e)

## Overview

tmux-worktree provides a terminal UI for git worktree management directly inside tmux. It uses `fzf` for interactive branch selection and `tmux display-popup` for a floating window experience.

**Key Features:**
- Create worktrees with interactive base branch selection
- AI tool picker — choose between Claude Code, Gemini CLI, Aider, Codex CLI, OpenCode, or a plain shell when opening a worktree (only installed tools are shown as selectable)
- Gitignored file sync — symlink or copy gitignored files (e.g. `.env`, build artifacts) into new worktrees, with per-file mode selection and reusable per-repo config
- Switch between existing worktrees (opens or focuses tmux window)
- Remove worktrees with multiselect support (remove one or many at once)
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
4. Choose how to handle gitignored files — load a saved config, create a new one (pick symlink/copy/skip per file), or skip
5. Select a tool to open with (skipped if only one is available)
6. Worktree is created, selected files are synced, and a new tmux window opens with the selected tool

### Switch workflow

1. Press `prefix + w`
2. Select a worktree from the list (`*` = dirty, window icon = tmux window open)
3. Jumps to existing window, or select a tool and open a new one

### Remove workflow

1. Press `prefix + X`
2. Select worktree(s) to remove (use **Tab** to select multiple, or just press Enter for single)
3. Confirm deletion (explicit force-remove prompt if any worktree has uncommitted changes)
4. Worktree directories and tmux windows are cleaned up
5. Branches are deleted with safe delete; if unmerged, prompts for force delete per branch or keeps it

### Gitignored file sync

Git worktrees don't share gitignored files (`.env`, build output, etc.) with the main worktree. During creation, the plugin offers to sync these files:

- **Load config** — reuse a previously saved per-repo config
- **Create config** — interactively pick a mode for each ignored file:
  - **Symlink** (`s`) — creates a symlink to the original file (shares changes)
  - **Copy** (`c`) — copies the file (independent snapshot)
  - **Skip** (`d`) — don't sync this file
- **Skip** — create the worktree without syncing any files

Configs are stored in `$XDG_CONFIG_HOME/tmux-worktree/` (defaults to `~/.config/tmux-worktree/`) and are reusable across worktrees in the same repo.

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
2. Run `./setup.sh` to configure git hooks
3. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
