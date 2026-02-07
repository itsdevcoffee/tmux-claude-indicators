#!/usr/bin/env bash
# Claude Code SessionStart hook - initializes window state
# Sets initial state to "active" and cleans up any previous processes

set -euo pipefail

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Cleanup trap handler
cleanup() {
    [ -f "${PID_FILE:-}" ] && rm -f "$PID_FILE" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Check if indicators are enabled
if [ "$(tmux show -gv @claude-enabled 2>/dev/null)" != "on" ]; then
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

# Set per-pane state (pane option, survives aggregation)
tmux set-option -p -t "$TMUX_PANE" @claude-pane-state "active" 2>/dev/null || true
tmux set-option -p -t "$TMUX_PANE" @claude-pane-emoji "🤖" 2>/dev/null || true

# Aggregate all panes and update window display
"$SCRIPT_DIR/bin/claude-aggregate-state" "$TMUX_PANE"

# Set deep purple/indigo background for active state (robot ready)
# Using colour256 instead of hex to avoid corrupting tmux's range declarations
tmux set-window-option -t "$TMUX_PANE" window-status-style "bg=colour54,fg=colour255,bold" 2>/dev/null || true

# Get window ID for animator cleanup (window-level, not pane-level)
WINDOW=$(tmux display-message -t "$TMUX_PANE" -p '#{window_id}' 2>/dev/null) || exit 1

# Kill any previous animator
PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-animator-${WINDOW}.pid"
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
