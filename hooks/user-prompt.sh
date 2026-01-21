#!/bin/bash
# Claude Code UserPromptSubmit/PreToolUse hook - fires when user submits input or Claude uses a tool
# Starts thinking animation

set -euo pipefail

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

# Don't set @claude-emoji for thinking state - format string handles it directly

# Set hot pink background for intense processing vibe
tmux set-window-option -t "$TMUX_PANE" window-status-style "bg=#F706CF,fg=#FFFFFF,bold" 2>/dev/null || true

# Define lock/PID paths now that we have TMUX_PANE
LOCK_FILE="${TMUX_TMPDIR:-/tmp}/claude-animator-${TMUX_PANE}.lock"
PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-animator-${TMUX_PANE}.pid"

# Kill any previous animator gracefully, then force if needed
# Use SIGTERM first to allow clean lock release, SIGKILL as fallback
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE" 2>/dev/null | head -1)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        # Try graceful termination first (allows lock release)
        kill "$OLD_PID" 2>/dev/null || true
        # Wait for process to terminate (up to 100ms)
        for _ in {1..10}; do
            kill -0 "$OLD_PID" 2>/dev/null || break
            sleep 0.01
        done
        # Force kill if still alive
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

# Spawn new animator - it will acquire exclusive lock internally
# If another animator somehow exists, the new one will exit immediately
nohup "$ANIMATOR_SCRIPT" "$TMUX_PANE" > /dev/null 2>&1 &
NEW_PID=$!

# Atomic PID file write using temp file + rename
echo "$NEW_PID" > "${PID_FILE}.tmp"
mv -f "${PID_FILE}.tmp" "$PID_FILE"

exit 0
