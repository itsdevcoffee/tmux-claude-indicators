# Recommended Keybindings

## Quiet Toggle Operations

The plugin now supports quiet mode for enable/disable operations. Add these to your `~/.tmux.conf` or `~/.tmux.conf.local`:

```bash
# Enable Claude indicators (quiet, just shows "Claude indicators enabled")
bind M-K run-shell 'tmux set -g @claude-indicators-enabled on && /path/to/tmux-claude-indicators/bin/tmux-claude-indicators-on'

# Disable Claude indicators (quiet, removes all state)
bind M-k run-shell 'tmux set -g @claude-indicators-enabled off && /path/to/tmux-claude-indicators/bin/tmux-claude-cleanup-all && tmux display-message "Claude indicators disabled"'

# Clear current window state (when you want to reset)
bind C run-shell 'tmux set-window-option -t "#{window_id}" @claude-state "active" && tmux set-window-option -t "#{window_id}" -u window-status-style && tmux display-message "Claude state cleared"'

# Clear all window states (clean slate)
bind M-c run-shell '/path/to/tmux-claude-indicators/bin/tmux-claude-cleanup-all'
```

## Keybinding Explained

| Binding | Action | Output |
|---------|--------|--------|
| `prefix + Alt+K` | Enable indicators | Single message: "Claude indicators enabled - Cyberpunk theme" |
| `prefix + Alt+k` | Disable indicators | Single message: "Claude indicators disabled" |
| `prefix + C` | Clear current window | Single message: "Claude state cleared" |
| `prefix + Alt+c` | Clear all windows | Silent, just cleans up |

## What Changed

### Before (Verbose)

Disabling and re-enabling would output ~20 lines:
```
🎨 Installing tmux-claude-indicators...
⚠ Warning: Claude Code (clod) not found...
📦 Backing up existing settings...
🔗 Injecting Claude Code hooks...
✓ Hooks injected successfully
🎨 Applying tmux status bar formats...
✓ Installation complete!
🎉 Claude Code indicators are now active!
Controls: ...
States: ...
```

### After (Quiet)

Enable/disable now shows just:
```
[Claude indicators enabled - Cyberpunk theme]
```

Or:
```
[Claude indicators disabled]
```

## Technical Details

The quiet mode works by:
1. Install script checks if hooks are already configured
2. If yes, runs in `--quiet` mode (suppresses all output except errors)
3. First-time installation still shows full output for visibility
4. Subsequent reloads (e.g., when sourcing config) are silent

## Migration

If you have the old keybindings with `tmux source-file ~/.tmux.conf`, you can:

**Option 1: Keep existing keybindings** (now quiet with auto-detection)
- The plugin will detect it's already installed and run quietly

**Option 2: Remove config reload** (slightly faster)
```bash
# Old disable keybinding:
bind M-k run-shell '... && tmux source-file ~/.tmux.conf && ...'

# New disable keybinding (remove the source-file part):
bind M-k run-shell 'tmux set -g @claude-indicators-enabled off && /path/to/tmux-claude-indicators/bin/tmux-claude-cleanup-all && tmux display-message "Claude indicators disabled"'
```

The config reload (`tmux source-file ~/.tmux.conf`) was causing the verbose output because it re-ran the installation script. Now that the script auto-detects and runs quietly, the reload is harmless but unnecessary.
