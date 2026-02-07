#!/usr/bin/env bash
# Claude Code Notification hook - fires when Claude is waiting for input
# Updates tmux window state to show waiting/needs attention

set -euo pipefail

# Cleanup trap handler
cleanup() {
    [ -f "${ANIMATOR_PID_FILE:-}" ] && rm -f "$ANIMATOR_PID_FILE" 2>/dev/null || true
    [ -f "${TIMER_PID_FILE:-}" ] && rm -f "$TIMER_PID_FILE" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Kill window animator helper function
kill_window_animator() {
    local window="$1"
    local pid_file="${TMUX_TMPDIR:-/tmp}/claude-animator-${window}.pid"

    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file" 2>/dev/null | head -1)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$pid_file"
    fi
}

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
    # Get script directory for relative paths
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    # Get window ID for animator cleanup
    WINDOW=$(tmux display-message -t "$TMUX_PANE" -p '#{window_id}' 2>/dev/null) || exit 1

    # Kill thinking animator if running (window-level)
    ANIMATOR_PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-animator-${WINDOW}.pid"
    kill_window_animator "$WINDOW"

    # Kill any previous escalation timer
    TIMER_PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-timer-${TMUX_PANE}.pid"
    if [ -f "$TIMER_PID_FILE" ]; then
        local timer_pid=$(cat "$TIMER_PID_FILE" 2>/dev/null | head -1)
        [ -n "$timer_pid" ] && kill -0 "$timer_pid" 2>/dev/null && kill "$timer_pid" 2>/dev/null || true
        rm -f "$TIMER_PID_FILE"
    fi

    # Set per-pane state (pane option, survives aggregation)
    tmux set-option -p -t "$TMUX_PANE" @claude-pane-state "question" 2>/dev/null || true
    tmux set-option -p -t "$TMUX_PANE" @claude-pane-emoji "🔮" 2>/dev/null || true

    # Aggregate all panes and update window display
    "$SCRIPT_DIR/bin/claude-aggregate-state" "$TMUX_PANE"

    # Set timestamp for state change
    tmux set-window-option -t "$TMUX_PANE" @claude-timestamp "$(date +%s)" 2>/dev/null || true

    # Set deep violet mystery background (initial question state)
    # Using colour256 instead of hex to avoid corrupting tmux's range declarations
    tmux set-window-option -t "$TMUX_PANE" window-status-style "bg=colour128,fg=colour255,bold,blink" 2>/dev/null || true

    # Start 15-second timer in background to escalate if unanswered
    (
        sleep 15
        # Check if this pane is still in question state after 15 seconds
        current_pane_state=$(tmux show-option -p -t "$TMUX_PANE" -v @claude-pane-state 2>/dev/null)
        if [ "$current_pane_state" = "question" ]; then
            # Escalate to laser blue cool hold (waiting state)
            tmux set-option -p -t "$TMUX_PANE" @claude-pane-state "waiting" 2>/dev/null || true
            tmux set-option -p -t "$TMUX_PANE" @claude-pane-emoji "🫦" 2>/dev/null || true
            # Re-aggregate to update window display
            "$SCRIPT_DIR/bin/claude-aggregate-state" "$TMUX_PANE"
            # Using colour256 instead of hex to avoid corrupting tmux's range declarations
            tmux set-window-option -t "$TMUX_PANE" window-status-style "bg=colour33,fg=colour255,bold,blink" 2>/dev/null || true
        fi
        rm -f "$TIMER_PID_FILE" 2>/dev/null
    ) &
    echo $! > "$TIMER_PID_FILE"

# Handle idle_prompt - set to active state
elif [ "$notification_type" = "idle_prompt" ]; then
    # Get script directory for relative paths
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    # Get window ID for animator cleanup
    WINDOW=$(tmux display-message -t "$TMUX_PANE" -p '#{window_id}' 2>/dev/null) || exit 1

    # Kill thinking animator if running (window-level)
    ANIMATOR_PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-animator-${WINDOW}.pid"
    kill_window_animator "$WINDOW"

    # Set per-pane state (pane option, survives aggregation)
    tmux set-option -p -t "$TMUX_PANE" @claude-pane-state "active" 2>/dev/null || true
    tmux set-option -p -t "$TMUX_PANE" @claude-pane-emoji "🤖" 2>/dev/null || true

    # Aggregate all panes and update window display
    "$SCRIPT_DIR/bin/claude-aggregate-state" "$TMUX_PANE"

    # Set deep purple/indigo background for active state (robot ready)
    # Using colour256 instead of hex to avoid corrupting tmux's range declarations
    tmux set-window-option -t "$TMUX_PANE" window-status-style "bg=colour54,fg=colour255,bold" 2>/dev/null || true
fi

exit 0
