#!/usr/bin/env bash
# Claude Code UserPromptSubmit/PreToolUse hook - fires when user submits input or Claude uses a tool
# Starts thinking animation

set -euo pipefail

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
tmux set-option -p -t "$TMUX_PANE" @claude-pane-state "thinking" 2>/dev/null || true
tmux set-option -p -t "$TMUX_PANE" @claude-pane-emoji "⠹" 2>/dev/null || true

# Aggregate all panes and update window display
"$SCRIPT_DIR/bin/claude-aggregate-state" "$TMUX_PANE"

# Set hot pink background for intense processing vibe
# Using colour256 instead of hex to avoid corrupting tmux's range declarations
tmux set-window-option -t "$TMUX_PANE" window-status-style "bg=colour200,fg=colour255,bold" 2>/dev/null || true

# Check if aggregator set the needs-animator flag
# Get the window ID for animator management (now window-level, not pane-level)
WINDOW=$(tmux display-message -t "$TMUX_PANE" -p '#{window_id}' 2>/dev/null) || exit 1
NEEDS_ANIMATOR=$(tmux show-window-option -t "$WINDOW" -v @claude-needs-animator 2>/dev/null)

if [ "$NEEDS_ANIMATOR" = "on" ]; then
    # Define PID path for window-level animator
    PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-animator-${WINDOW}.pid"

    # Kill any previous animator gracefully, then force if needed
    if [ -f "$PID_FILE" ]; then
        OLD_PID=$(cat "$PID_FILE" 2>/dev/null | head -1)
        if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
            # Try graceful SIGTERM first (allows clean lock release)
            kill "$OLD_PID" 2>/dev/null || true
            # Wait for termination (up to 100ms), then force kill if needed
            for _ in {1..10}; do
                kill -0 "$OLD_PID" 2>/dev/null || break
                sleep 0.01
            done
            kill -9 "$OLD_PID" 2>/dev/null || true
        fi
        rm -f "$PID_FILE"
    fi

    # Verify animator script exists before spawning
    ANIMATOR_SCRIPT="$SCRIPT_DIR/bin/claude-thinking-animator"
    if [ ! -x "$ANIMATOR_SCRIPT" ]; then
        echo "Error: Animator script not found or not executable: $ANIMATOR_SCRIPT" >&2
        exit 1
    fi

    # Spawn new animator - pass window ID instead of pane ID
    # It will acquire exclusive lock internally
    nohup "$ANIMATOR_SCRIPT" "$WINDOW" > /dev/null 2>&1 &
    NEW_PID=$!

    # Atomic PID file write using temp file + rename
    echo "$NEW_PID" > "${PID_FILE}.tmp"
    mv -f "${PID_FILE}.tmp" "$PID_FILE"

    # Clear the flag
    tmux set-window-option -t "$WINDOW" -u @claude-needs-animator 2>/dev/null || true
fi

exit 0
