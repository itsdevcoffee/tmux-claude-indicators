# tmux-claude-code

> Visual state indicators for Claude Code in tmux status bar

Never miss when Claude is thinking, waiting for permission, or needs your attention. This tmux plugin adds real-time emoji indicators to your status bar that show Claude Code's current state.

## Features

**Cyberpunk/TRON-inspired theme with vibrant state indicators:**

- **🤖 Active** - Claude ready to work (deep purple #300B5F)
- **😜🤪😵‍💫 Thinking** - Animated while processing (hot pink #F706CF)
- **🔮 Question** - Needs permission (deep violet #791E94, blinks)
- **🫦 Waiting** - Question unanswered >15s (laser blue #035EE8, blinks)
- **✅ Complete** - Task finished (matrix green #02F78E flash, 3s)

**Smart focus indicator:**
- **Non-current windows:** Colored backgrounds show state at-a-glance
- **Current window:** ▶ Arrow + colored text + transparent background
- **No Claude:** Rust brown theme (#8B4513) for non-Claude windows

## Preview

```
Non-current: │ 1 dotfiles 🤖  │ 2 api 😜  │ 3 frontend 🔮
              ▼ colored bg     ▼ pink bg   ▼ violet bg

Current:     ▶ 4 backend ✅
              ▼ arrow + colored text + no bg (stands out!)
```

## Requirements

- **tmux** 3.0+ (3.3+ recommended for heavy borders)
- **Claude Code CLI** (`clod`)
- **bash** 4.0+
- **Python 3** (for automatic hook injection, optional)

## Installation

### Via TPM (Tmux Plugin Manager)

1. Add plugin to `.tmux.conf`:
   ```tmux
   set -g @plugin 'itsdevcoffee/tmux-claude-code'
   ```

2. Press `prefix + I` to install (default: `Ctrl-b I`)

3. Restart Claude Code sessions to load hooks

### Manual Installation

```bash
# Clone repository
git clone https://github.com/itsdevcoffee/tmux-claude-code ~/.tmux/plugins/tmux-claude-code

# Run installation script
~/.tmux/plugins/tmux-claude-code/scripts/install.sh

# Reload tmux config
tmux source-file ~/.tmux.conf

# Restart Claude Code sessions
```

## Quick Start

After installation, keybindings are **automatically configured**:

1. **Start Claude Code** in a tmux window
2. **Submit a prompt** and watch the status bar change:
   - 🤖 (deep purple) → 😜 (hot pink, animated) → ✅ (matrix green flash)

The plugin is enabled by default. Use the keybindings below to control it.

## Keybindings

**Automatically configured** - no manual setup required!

| Keybinding | Action |
|------------|--------|
| `prefix + Alt+Shift+K` | Enable indicators |
| `prefix + Alt+K` | Disable indicators |
| `prefix + Alt+C` | Clear current window state |
| `prefix + Alt+Shift+C` | Clear all window states |

*Default prefix: `Ctrl-a` (or `Ctrl-b` on vanilla tmux)*

### Customize Keybindings

Change keybindings by setting these options in `.tmux.conf` **before** loading the plugin:

```tmux
# Customize keybindings (set to empty string "" to disable)
set -g @claude-key-enable "M-K"       # Alt+Shift+K (default)
set -g @claude-key-disable "M-k"      # Alt+K (default)
set -g @claude-key-clear "M-c"        # Alt+C (default)
set -g @claude-key-clear-all "M-C"    # Alt+Shift+C (default)

# Load plugin (must be after customization)
set -g @plugin 'itsdevcoffee/tmux-claude-code'
```

**Key format guide:**
- `M-k` = Alt+K
- `M-K` = Alt+Shift+K
- `C-k` = Ctrl+K
- `k` = Just K (with prefix)

## Configuration

### Customization Options

Add these to your `.tmux.conf` **before** loading the plugin to customize:

**Note:** Set options before `set -g @plugin` line for them to take effect.

```tmux
# Enable/disable (default: on)
set -g @claude-enabled "on"

# Emoji customization
set -g @claude-emoji-active "🤖"
set -g @claude-emoji-thinking "😜 🤪 😵‍💫"
set -g @claude-emoji-question "🔮"
set -g @claude-emoji-waiting "🫦"
set -g @claude-emoji-complete "✅"

# Color customization - Cyberpunk/TRON theme (hex codes)
set -g @claude-color-active-bg "#300B5F"      # Deep purple
set -g @claude-color-active-fg "#FFFFFF"      # White
set -g @claude-color-thinking-bg "#F706CF"    # Hot pink
set -g @claude-color-thinking-fg "#FFFFFF"    # White
set -g @claude-color-question-bg "#791E94"    # Deep violet
set -g @claude-color-question-fg "#FFFFFF"    # White
set -g @claude-color-waiting-bg "#035EE8"     # Laser blue
set -g @claude-color-waiting-fg "#FFFFFF"     # White
set -g @claude-color-complete-bg "#02F78E"    # Matrix green
set -g @claude-color-complete-fg "#000000"    # Black

# Timing
set -g @claude-interval "160"      # Animation speed (ms)
set -g @claude-escalation "15"     # Question→waiting timeout (s)

# Debug mode
set -g @claude-debug "off"
```

### Integration with Other Themes

This plugin automatically overrides `window-status-format` and `window-status-current-format`. If you use tmux themes (like tmux2k), enable indicators with `prefix + K` *after* tmux starts to override the theme.

To make indicators permanent, add to `.tmux.conf`:
```tmux
# Apply indicators after theme loads
run-shell '~/.tmux/plugins/tmux-claude-code/bin/tmux-claude-code-on'
```

## How It Works

### Architecture

1. **Claude Code Hooks** - Bash scripts triggered by Claude events:
   - `SessionStart` → Set state to "active"
   - `UserPromptSubmit` → Start thinking animation
   - `PreToolUse` → Continue thinking (handles question→thinking transitions)
   - `Notification` → Handle permission prompts
   - `Stop` → Show completion flash

2. **Background Processes**:
   - **Animator** - Rotates emoji frames every 160ms while thinking
   - **Escalation Timer** - Escalates question to "waiting" after 15s
   - **Flash Timer** - Clears completion flash after 3s

3. **tmux Integration**:
   - Hooks update `@claude-state` window variable
   - Format strings check state and display corresponding emoji/color
   - PID files in `${TMUX_TMPDIR}` track background processes

### State Machine

```
active (🤖, deep purple #300B5F)
  ↓ UserPromptSubmit
thinking (😜🤪😵‍💫 animated, hot pink #F706CF)
  ↓ Notification:permission_prompt
question (🔮, deep violet #791E94, blinks)
  ↓ [15s timeout]
waiting (🫦, laser blue #035EE8, blinks)
  ↓ PreToolUse
thinking
  ↓ Stop
complete (✅, matrix green #02F78E flash, 3s)
  ↓ SessionStart
active
```

## Troubleshooting

### Indicators not showing

1. Check if enabled:
   ```bash
   tmux show -gv @claude-enabled
   # Should show: on
   ```

2. Enable manually:
   ```tmux
   prefix + Alt+Shift+K
   ```

3. Restart Claude Code sessions (hooks load at startup)

### Multiple animators running

```bash
# Check for orphaned processes
pgrep -f claude-thinking-animator

# Clean up
pkill -f claude-thinking-animator
rm ${TMUX_TMPDIR:-/tmp}/claude-animator-*.pid

# Restart Claude Code
```

### Hooks not firing

1. Verify hooks in `~/.claude/settings.json`:
   ```bash
   cat ~/.claude/settings.json | grep tmux-claude-code
   ```

2. Re-run installation:
   ```bash
   ~/.tmux/plugins/tmux-claude-code/scripts/install.sh
   ```

3. Check hook script permissions:
   ```bash
   ls -l ~/.tmux/plugins/tmux-claude-code/hooks/
   # Should be executable (chmod +x)
   ```

### Emoji not rendering

- **Kitty**: ✅ Full emoji support
- **iTerm2**: ✅ Full emoji support
- **Alacritty**: Requires emoji font (e.g., Noto Color Emoji)
- **Old terminals**: May show boxes - customize with ASCII:
  ```tmux
  set -g @claude-emoji-thinking "..."
  set -g @claude-emoji-question "?"
  set -g @claude-emoji-waiting "!!"
  ```

### Debug mode

Enable detailed logging:

```tmux
set -g @claude-debug "on"
```

Then check logs:
```bash
tail -f ${TMUX_TMPDIR:-/tmp}/tmux-claude-code-debug.log
```

## Uninstall

```bash
# Run uninstall script
~/.tmux/plugins/tmux-claude-code/scripts/uninstall.sh

# Remove from .tmux.conf
# Delete this line: set -g @plugin 'itsdevcoffee/tmux-claude-code'

# Reload tmux
tmux source-file ~/.tmux.conf
```

## Performance

- **Hook execution**: <30ms per event (non-blocking)
- **Memory footprint**: ~4.5MB per session (3 windows with animators)
- **CPU usage**: <0.02% (background processes idle 99.7% of time)
- **Scalability**: Tested with 50+ concurrent Claude sessions

## Security

- No external dependencies (except Python for auto-config, which is optional)
- PID files use `${TMUX_TMPDIR}` for user isolation
- Hooks run with user permissions (no privilege escalation)
- All processes properly tracked and cleaned up

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

MIT License - see [LICENSE](LICENSE) for details

## Credits

Created by [Dev Coffee](https://github.com/itsdevcoffee)

Inspired by the need for better visual feedback when using Claude Code in tmux.

## Changelog

### v1.0.0 (2025-01-16)

- Initial release
- Support for all 5 Claude states
- Animated thinking indicator
- Auto-escalation for unanswered questions
- TPM and manual installation
- Full customization support
- Comprehensive documentation

## Links

- [GitHub Repository](https://github.com/itsdevcoffee/tmux-claude-code)
- [Issues](https://github.com/itsdevcoffee/tmux-claude-code/issues)
- [Claude Code Documentation](https://code.claude.com/docs)
- [tmux Documentation](https://github.com/tmux/tmux/wiki)

---

**Star ⭐ this repo if you find it useful!**
