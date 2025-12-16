#!/bin/bash
# Claude Code SessionStart hook - initializes window state
# Sets initial state to "active" and cleans up any previous processes

set -euo pipefail

# Cleanup trap handler
cleanup() {
    [ -f "${PID_FILE:-}" ] && rm -f "$PID_FILE" 2>/dev/null || true
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

# Read hook input (not used but required for hooks)
cat > /dev/null

# Set initial state to active (Claude is idle, waiting for input)
if ! tmux set-window-option -t "$TMUX_PANE" @claude-state "active" 2>/dev/null; then
    echo "Warning: Failed to set window state for pane $TMUX_PANE" >&2
fi

# Clear any previous styling
tmux set-window-option -t "$TMUX_PANE" -u window-status-style 2>/dev/null || true

# Kill any previous animator
PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-animator-${TMUX_PANE}.pid"
if [ -f "$PID_FILE" ]; then
    ANIMATOR_PID=$(cat "$PID_FILE" 2>/dev/null | head -1)
    # FIX: Use kill -0 to check if process exists
    if [ -n "$ANIMATOR_PID" ] && kill -0 "$ANIMATOR_PID" 2>/dev/null; then
        kill "$ANIMATOR_PID" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
fi

# Exit immediately without waiting
exit 0
