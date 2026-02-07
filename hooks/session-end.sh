#!/usr/bin/env bash
# Claude Code SessionEnd hook - fires when session terminates
# Clears pane state and re-aggregates window display
set -euo pipefail

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Cleanup trap handler
cleanup() {
    [ -f "${PID_FILE:-}" ] && rm -f "$PID_FILE" 2>/dev/null || true
    [ -f "${TIMER_PID_FILE:-}" ] && rm -f "$TIMER_PID_FILE" 2>/dev/null || true
    [ -f "${FLASH_PID_FILE:-}" ] && rm -f "$FLASH_PID_FILE" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Check if indicators are enabled
if [ "$(tmux show -gv @claude-enabled 2>/dev/null)" != "on" ]; then
    cat > /dev/null
    exit 0
fi

TMUX_PANE="${TMUX_PANE:-}"
[ -z "$TMUX_PANE" ] && exit 0

# Read hook input (JSON from Claude Code)
hook_input=$(cat)

# Get window ID for process cleanup
WINDOW=$(tmux display-message -t "$TMUX_PANE" -p '#{window_id}' 2>/dev/null) || exit 0

# Kill thinking animator if running (window-level)
PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-animator-${WINDOW}.pid"
if [ -f "$PID_FILE" ]; then
    ANIMATOR_PID=$(cat "$PID_FILE" 2>/dev/null | head -1)
    if [ -n "$ANIMATOR_PID" ] && kill -0 "$ANIMATOR_PID" 2>/dev/null; then
        kill "$ANIMATOR_PID" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
fi

# Kill escalation timer if running
TIMER_PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-timer-${TMUX_PANE}.pid"
if [ -f "$TIMER_PID_FILE" ]; then
    TIMER_PID=$(cat "$TIMER_PID_FILE" 2>/dev/null | head -1)
    if [ -n "$TIMER_PID" ] && kill -0 "$TIMER_PID" 2>/dev/null; then
        kill "$TIMER_PID" 2>/dev/null || true
    fi
    rm -f "$TIMER_PID_FILE"
fi

# Kill flash timer if running
FLASH_PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-flash-${TMUX_PANE}.pid"
if [ -f "$FLASH_PID_FILE" ]; then
    FLASH_PID=$(cat "$FLASH_PID_FILE" 2>/dev/null | head -1)
    if [ -n "$FLASH_PID" ] && kill -0 "$FLASH_PID" 2>/dev/null; then
        kill "$FLASH_PID" 2>/dev/null || true
    fi
    rm -f "$FLASH_PID_FILE"
fi

# Clear pane-level state (Claude is gone from this pane)
tmux set-option -p -t "$TMUX_PANE" -u @claude-pane-state 2>/dev/null || true
tmux set-option -p -t "$TMUX_PANE" -u @claude-pane-emoji 2>/dev/null || true

# Clear thinking frame
tmux set-window-option -t "$TMUX_PANE" -u @claude-thinking-frame 2>/dev/null || true

# Re-aggregate window display (will drop this pane from count)
"$SCRIPT_DIR/bin/claude-aggregate-state" "$TMUX_PANE"

# Clear window-status-style so it falls back to format string colors
tmux set-window-option -t "$TMUX_PANE" -u window-status-style 2>/dev/null || true

exit 0
