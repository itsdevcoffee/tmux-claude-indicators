#!/usr/bin/env bash
# Uninstall script for tmux-claude-indicators

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS_FILE="${HOME}/.claude/settings.json"
TMPDIR="${TMUX_TMPDIR:-/tmp}"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "🗑️  Uninstalling tmux-claude-indicators..."

# Kill all background processes
echo "🔪 Stopping background processes..."
pkill -f claude-thinking-animator 2>/dev/null
pkill -f "sleep 15.*claude.*timer" 2>/dev/null

# Remove PID files
echo "🧹 Cleaning up PID files..."
rm -f "$TMPDIR"/claude-animator-*.pid
rm -f "$TMPDIR"/claude-timer-*.pid
rm -f "$TMPDIR"/claude-flash-*.pid

# Clear tmux state
if [ -n "$TMUX" ]; then
    echo "🎨 Clearing tmux window states..."
    for win_id in $(tmux list-windows -a -F "#{window_id}" 2>/dev/null); do
        tmux set-window-option -t "$win_id" -u @claude-state 2>/dev/null
        tmux set-window-option -t "$win_id" -u @claude-thinking-frame 2>/dev/null
        tmux set-window-option -t "$win_id" -u @claude-timestamp 2>/dev/null
        tmux set-window-option -t "$win_id" -u window-status-style 2>/dev/null
    done

    # Remove global options
    tmux set -gu @claude-indicators-enabled 2>/dev/null
    tmux set -gu @claude-indicators-debug 2>/dev/null
    tmux set -gu @claude-indicators-interval 2>/dev/null
    tmux set -gu @claude-indicators-escalation 2>/dev/null

    # Reload tmux config to restore original formats
    echo "🔄 Reloading tmux configuration..."
    tmux source-file ~/.tmux.conf 2>/dev/null || true
fi

# Remove hooks from settings.json
if [ -f "$SETTINGS_FILE" ]; then
    echo "🔗 Removing hooks from Claude Code settings..."

    # Backup before modification
    BACKUP="${SETTINGS_FILE}.backup-uninstall-$(date +%Y%m%d-%H%M%S)"
    cp "$SETTINGS_FILE" "$BACKUP"
    echo "   Backup saved: $BACKUP"

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$SETTINGS_FILE" "$PLUGIN_DIR" <<'EOF'
import json
import sys

settings_file = sys.argv[1]
plugin_dir = sys.argv[2]

# Read settings
with open(settings_file, 'r') as f:
    settings = json.load(f)

# Remove our hooks
if 'hooks' in settings:
    for event in ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'Stop', 'Notification']:
        if event in settings['hooks']:
            # Filter out our hooks
            settings['hooks'][event] = [
                h for h in settings['hooks'][event]
                if not (isinstance(h, dict) and
                       'hooks' in h and
                       h['hooks'] and
                       plugin_dir in h['hooks'][0].get('command', ''))
            ]
            # Remove empty hook arrays
            if not settings['hooks'][event]:
                del settings['hooks'][event]

# Write updated settings atomically (prevent corruption)
import os
import tempfile

# Write to temporary file first
temp_fd, temp_path = tempfile.mkstemp(dir=os.path.dirname(settings_file), prefix='.settings.json.tmp')
try:
    with os.fdopen(temp_fd, 'w') as f:
        json.dump(settings, f, indent=2)
    # Atomic rename (POSIX guarantees atomicity)
    os.rename(temp_path, settings_file)
    print("   ✓ Hooks removed from settings.json")
except Exception as e:
    # Clean up temp file on error
    if os.path.exists(temp_path):
        os.unlink(temp_path)
    raise
EOF
    else
        echo -e "   ${YELLOW}⚠ Python not found - please manually remove hooks from settings.json${NC}"
    fi
fi

echo -e "${GREEN}✓ Uninstall complete!${NC}"
echo ""
echo "To completely remove the plugin:"
echo "  1. Remove from .tmux.conf: set -g @plugin 'maskkiller/tmux-claude-indicators'"
echo "  2. Restart tmux or run: tmux source-file ~/.tmux.conf"
echo "  3. (Optional) Remove plugin directory: ~/.tmux/plugins/tmux-claude-indicators"
echo ""
echo "Backups saved:"
echo "  Settings: $BACKUP"
echo ""
echo "Restart Claude Code sessions to unload hooks completely."
