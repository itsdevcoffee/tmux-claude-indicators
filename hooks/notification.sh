#!/bin/bash
# Claude Code Notification hook - fires when Claude is waiting for input
# Updates tmux window state to show waiting/needs attention

set -euo pipefail

# Cleanup trap handler
cleanup() {
    [ -f "${ANIMATOR_PID_FILE:-}" ] && rm -f "$ANIMATOR_PID_FILE" 2>/dev/null || true
    [ -f "${TIMER_PID_FILE:-}" ] && rm -f "$TIMER_PID_FILE" 2>/dev/null || true
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

# Check notification type (no jq dependency - simple grep)
if echo "$hook_input" | grep -q '"notification_type":"permission_prompt"'; then
    notification_type="permission_prompt"
elif echo "$hook_input" | grep -q '"notification_type":"idle_prompt"'; then
    notification_type="idle_prompt"
else
    notification_type="unknown"
fi

# Handle permission_prompt as question state
if [ "$notification_type" = "permission_prompt" ]; then
    # Kill thinking animator if running
    ANIMATOR_PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-animator-${TMUX_PANE}.pid"
    if [ -f "$ANIMATOR_PID_FILE" ]; then
        ANIMATOR_PID=$(cat "$ANIMATOR_PID_FILE" 2>/dev/null | head -1)
        # FIX: Use kill -0 to check if process exists
        if [ -n "$ANIMATOR_PID" ] && kill -0 "$ANIMATOR_PID" 2>/dev/null; then
            kill "$ANIMATOR_PID" 2>/dev/null || true
        fi
        rm -f "$ANIMATOR_PID_FILE"
    fi

    # Kill any previous escalation timer
    TIMER_PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-timer-${TMUX_PANE}.pid"
    if [ -f "$TIMER_PID_FILE" ]; then
        TIMER_PID=$(cat "$TIMER_PID_FILE" 2>/dev/null | head -1)
        # FIX: Use kill -0 to check if process exists
        if [ -n "$TIMER_PID" ] && kill -0 "$TIMER_PID" 2>/dev/null; then
            kill "$TIMER_PID" 2>/dev/null || true
        fi
        rm -f "$TIMER_PID_FILE"
    fi

    # Set question state
    if ! tmux set-window-option -t "$TMUX_PANE" @claude-state "question" 2>/dev/null; then
        echo "Warning: Failed to set question state for pane $TMUX_PANE" >&2
    fi
    tmux set-window-option -t "$TMUX_PANE" @claude-timestamp "$(date +%s)" 2>/dev/null || true

    # Set blinking bright purple synthwave style (initial question state)
    tmux set-window-option -t "$TMUX_PANE" window-status-style "bg=#b537f2,fg=#000000,bold,blink" 2>/dev/null || true

    # Start 15-second timer in background to escalate if unanswered
    (
        sleep 15
        # Check if still in question state after 15 seconds
        current_state=$(tmux show-window-option -t "$TMUX_PANE" -v @claude-state 2>/dev/null)
        if [ "$current_state" = "question" ]; then
            # Escalate to urgent magenta synthwave background (waiting state)
            tmux set-window-option -t "$TMUX_PANE" @claude-state "waiting" 2>/dev/null || true
            tmux set-window-option -t "$TMUX_PANE" window-status-style "bg=#9C0841,fg=#FFFFFF,bold,blink" 2>/dev/null || true
        fi
        rm -f "$TIMER_PID_FILE" 2>/dev/null
    ) &
    echo $! > "$TIMER_PID_FILE"

# Handle idle_prompt - set to active state
elif [ "$notification_type" = "idle_prompt" ]; then
    # Kill thinking animator if running
    ANIMATOR_PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-animator-${TMUX_PANE}.pid"
    if [ -f "$ANIMATOR_PID_FILE" ]; then
        ANIMATOR_PID=$(cat "$ANIMATOR_PID_FILE" 2>/dev/null | head -1)
        # FIX: Use kill -0 to check if process exists
        if [ -n "$ANIMATOR_PID" ] && kill -0 "$ANIMATOR_PID" 2>/dev/null; then
            kill "$ANIMATOR_PID" 2>/dev/null || true
        fi
        rm -f "$ANIMATOR_PID_FILE"
    fi

    # Set to active state (Claude is idle, ready for input)
    if ! tmux set-window-option -t "$TMUX_PANE" @claude-state "active" 2>/dev/null; then
        echo "Warning: Failed to set active state for pane $TMUX_PANE" >&2
    fi
    tmux set-window-option -t "$TMUX_PANE" -u window-status-style 2>/dev/null || true
fi

exit 0
