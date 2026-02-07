#!/usr/bin/env bash
# Claude Code Stop hook - fires when Claude finishes responding
# Updates tmux window state to show completion

set -euo pipefail

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Cleanup trap handler
cleanup() {
    [ -f "${PID_FILE:-}" ] && rm -f "$PID_FILE" 2>/dev/null || true
    [ -f "${FLASH_PID_FILE:-}" ] && rm -f "$FLASH_PID_FILE" 2>/dev/null || true
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

# Read hook input (JSON from Claude Code)
hook_input=$(cat)

# Set per-pane state (pane option, survives aggregation)
tmux set-option -p -t "$TMUX_PANE" @claude-pane-state "complete" 2>/dev/null || true
tmux set-option -p -t "$TMUX_PANE" @claude-pane-emoji "✅" 2>/dev/null || true

# Aggregate all panes and update window display
"$SCRIPT_DIR/bin/claude-aggregate-state" "$TMUX_PANE"

# Set timestamp for state change
tmux set-window-option -t "$TMUX_PANE" @claude-timestamp "$(date +%s)" 2>/dev/null || true

# Get window ID for animator cleanup
WINDOW=$(tmux display-message -t "$TMUX_PANE" -p '#{window_id}' 2>/dev/null) || exit 1

# Kill thinking animator if running (window-level)
PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-animator-${WINDOW}.pid"
if [ -f "$PID_FILE" ]; then
    ANIMATOR_PID=$(cat "$PID_FILE" 2>/dev/null | head -1)
    # FIX: Use kill -0 to check if process exists
    if [ -n "$ANIMATOR_PID" ] && kill -0 "$ANIMATOR_PID" 2>/dev/null; then
        kill "$ANIMATOR_PID" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
fi

# Flash the window (brief visual alert) - Matrix green hacker success
# Using colour256 instead of hex to avoid corrupting tmux's range declarations
tmux set-window-option -t "$TMUX_PANE" window-status-style "bg=colour48,fg=colour232,bold" 2>/dev/null || true

# Reset the flash after 3 seconds (runs in background)
# Track flash PID to allow cancellation if needed (use window ID for consistency)
FLASH_PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-flash-${WINDOW}.pid"
(sleep 3 && tmux set-window-option -t "$TMUX_PANE" -u window-status-style 2>/dev/null && rm -f "$FLASH_PID_FILE" 2>/dev/null) &
echo $! > "$FLASH_PID_FILE"

exit 0
