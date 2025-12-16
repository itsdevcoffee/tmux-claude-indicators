#!/bin/bash
# Claude Code UserPromptSubmit/PreToolUse hook - fires when user submits input or Claude uses a tool
# Starts thinking animation

set -euo pipefail

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

# Set state to thinking
if ! tmux set-window-option -t "$TMUX_PANE" @claude-state "thinking" 2>/dev/null; then
    echo "Warning: Failed to set window state for pane $TMUX_PANE" >&2
fi
tmux set-window-option -t "$TMUX_PANE" @claude-thinking-frame "😜" 2>/dev/null || true

# Clear any previous styling
tmux set-window-option -t "$TMUX_PANE" -u window-status-style 2>/dev/null || true

# Kill any previous animator (CRITICAL: PreToolUse fires multiple times!)
PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-animator-${TMUX_PANE}.pid"
if [ -f "$PID_FILE" ]; then
    ANIMATOR_PID=$(cat "$PID_FILE" 2>/dev/null | head -1)
    # FIX: Use kill -0 to check if process exists
    if [ -n "$ANIMATOR_PID" ] && kill -0 "$ANIMATOR_PID" 2>/dev/null; then
        kill "$ANIMATOR_PID" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
fi

# FIX: Atomic PID file creation to prevent race condition
# Create PID file with temporary marker, then update atomically
echo "$$" > "$PID_FILE"
nohup "$SCRIPT_DIR/bin/claude-thinking-animator" "$TMUX_PANE" > /dev/null 2>&1 &
ANIMATOR_PID=$!
echo "$ANIMATOR_PID" > "$PID_FILE"

exit 0
