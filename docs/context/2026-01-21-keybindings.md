# Automatic Keybindings

## Overview

The plugin now **automatically configures keybindings** - users don't need to manually add them to their config!

## Default Keybindings

| Keybinding | Action |
|------------|--------|
| `prefix + Alt+Shift+K` | Enable indicators |
| `prefix + Alt+K` | Disable indicators |
| `prefix + Alt+C` | Clear current window state |
| `prefix + Alt+Shift+C` | Clear all window states |

## How It Works

The plugin file (`claude-indicators.tmux`) automatically sets up keybindings using `$CURRENT_DIR` to reference scripts without hardcoded paths:

```bash
# In claude-indicators.tmux
tmux bind-key "M-K" run-shell "tmux set -g @claude-indicators-enabled on && '$CURRENT_DIR/bin/tmux-claude-indicators-on'"
```

This eliminates the need for users to add long keybinding commands with hardcoded paths to their `.tmux.conf`.

## User Customization

Users can customize keybindings by setting tmux options **before** loading the plugin:

```tmux
# In ~/.tmux.conf (before set -g @plugin line)
set -g @claude-key-enable "M-K"       # Alt+Shift+K (default)
set -g @claude-key-disable "M-k"      # Alt+K (default)
set -g @claude-key-clear "M-c"        # Alt+C (default)
set -g @claude-key-clear-all "M-C"    # Alt+Shift+C (default)

# To disable a keybinding, set it to empty string
set -g @claude-key-clear ""           # Disable clear current window
```

## Keybinding Output

| Binding | Action | Output |
|---------|--------|--------|
| `prefix + Alt+Shift+K` | Enable indicators | Single message: "Claude indicators enabled - Cyberpunk theme" |
| `prefix + Alt+K` | Disable indicators | Single message: "Claude indicators disabled" |
| `prefix + Alt+C` | Clear current window | Single message: "Claude state cleared" |
| `prefix + Alt+Shift+C` | Clear all windows | Silent, just cleans up |

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

## Migration from Manual Keybindings

If you previously had manual keybindings in your `.tmux.conf`:

**Option 1: Remove manual keybindings** (recommended)
- Delete the old `bind-key` lines from your config
- The plugin will automatically set up keybindings

**Option 2: Keep custom keybindings**
- Set the corresponding `@claude-key-*` options to empty string to disable automatic keybindings
- Keep your manual bindings

Example:
```tmux
# Disable automatic keybindings
set -g @claude-key-enable ""
set -g @claude-key-disable ""

# Keep your custom bindings
bind-key X run-shell '...'  # Your custom enable keybinding
bind-key Y run-shell '...'  # Your custom disable keybinding
```

## Why This Approach?

Following best practices from popular tmux plugins (tmux-resurrect, tmux-yank):
- **No hardcoded paths** - Plugin uses `$CURRENT_DIR` internally
- **Works with TPM** - Path resolution happens automatically
- **User-friendly** - Just install and use, no manual config needed
- **Customizable** - Advanced users can still override via tmux options
