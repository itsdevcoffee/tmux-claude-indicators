#!/bin/bash
# Claude Code Stop hook - fires when Claude finishes responding
# Updates tmux window state to show completion

set -euo pipefail

# Cleanup trap handler
cleanup() {
    [ -f "${PID_FILE:-}" ] && rm -f "$PID_FILE" 2>/dev/null || true
    [ -f "${FLASH_PID_FILE:-}" ] && rm -f "$FLASH_PID_FILE" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Check if indicators are enabled
if [ "$(tmux show -gv @claude-indicators-enabled 2>/dev/null)" != "on" ]; then
    cat > /dev/null  # Consume hook input
    exit 0
fi

# Get the current tmux pane
TMUX_PANE="${TMUX_PANE:-}"

if [ -z "$TMUX_PANE" ]; then
    exit 0
fi

# Read hook input (JSON from Claude Code)
hook_input=$(cat)

# Kill thinking animator if running
PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-animator-${TMUX_PANE}.pid"
if [ -f "$PID_FILE" ]; then
    ANIMATOR_PID=$(cat "$PID_FILE" 2>/dev/null | head -1)
    # FIX: Use kill -0 to check if process exists
    if [ -n "$ANIMATOR_PID" ] && kill -0 "$ANIMATOR_PID" 2>/dev/null; then
        kill "$ANIMATOR_PID" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
fi

# Set window user option to mark as completed
if ! tmux set-window-option -t "$TMUX_PANE" @claude-state "complete" 2>/dev/null; then
    echo "Warning: Failed to set complete state for pane $TMUX_PANE" >&2
fi

# Set timestamp for state change
tmux set-window-option -t "$TMUX_PANE" @claude-timestamp "$(date +%s)" 2>/dev/null || true

# Flash the window (brief visual alert) - Teal synthwave
tmux set-window-option -t "$TMUX_PANE" window-status-style "bg=#11dddd,fg=#000000,bold" 2>/dev/null || true

# Reset the flash after 3 seconds (runs in background)
# Track flash PID to allow cancellation if needed
FLASH_PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-flash-${TMUX_PANE}.pid"
(sleep 3 && tmux set-window-option -t "$TMUX_PANE" -u window-status-style 2>/dev/null && rm -f "$FLASH_PID_FILE" 2>/dev/null) &
echo $! > "$FLASH_PID_FILE"

exit 0
