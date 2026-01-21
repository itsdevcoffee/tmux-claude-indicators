#!/usr/bin/env bash
# tmux-claude-indicators - Visual state indicators for Claude Code in tmux
# TPM plugin entry point

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Helper function to get tmux option with default value
get_tmux_option() {
    local option="$1"
    local default="$2"
    local value=$(tmux show-option -gqv "$option")
    if [ -z "$value" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Set default options if not already set
tmux set-option -gq @claude-indicators-enabled "on"
tmux set-option -gq @claude-indicators-debug "off"

# Animation settings
tmux set-option -gq @claude-indicators-interval "160"
tmux set-option -gq @claude-indicators-escalation "15"

# Emoji settings
tmux set-option -gq @claude-indicators-emoji-active "🤖"
tmux set-option -gq @claude-indicators-emoji-thinking "😜 🤪 😵‍💫"
tmux set-option -gq @claude-indicators-emoji-question "🔮"
tmux set-option -gq @claude-indicators-emoji-waiting "🫦"
tmux set-option -gq @claude-indicators-emoji-complete "✅"

# Color settings - Cyberpunk/TRON aesthetic
tmux set-option -gq @claude-indicators-color-active-bg "#300B5F"      # Deep purple/indigo
tmux set-option -gq @claude-indicators-color-active-fg "#FFFFFF"      # White
tmux set-option -gq @claude-indicators-color-thinking-bg "#F706CF"    # Hot pink
tmux set-option -gq @claude-indicators-color-thinking-fg "#FFFFFF"    # White
tmux set-option -gq @claude-indicators-color-question-bg "#791E94"    # Deep violet
tmux set-option -gq @claude-indicators-color-question-fg "#FFFFFF"    # White
tmux set-option -gq @claude-indicators-color-waiting-bg "#035EE8"     # Laser blue
tmux set-option -gq @claude-indicators-color-waiting-fg "#FFFFFF"     # White
tmux set-option -gq @claude-indicators-color-complete-bg "#02F78E"    # Matrix green
tmux set-option -gq @claude-indicators-color-complete-fg "#000000"    # Black

# Keybinding settings - Set to empty string to disable a keybinding
tmux set-option -gq @claude-key-enable "M-K"       # Alt+Shift+K
tmux set-option -gq @claude-key-disable "M-k"      # Alt+K
tmux set-option -gq @claude-key-clear "M-c"        # Alt+C (clear current window)
tmux set-option -gq @claude-key-clear-all "M-C"    # Alt+Shift+C (clear all windows)

# Make scripts executable
chmod +x "$CURRENT_DIR/hooks/"*.sh
chmod +x "$CURRENT_DIR/bin/"*
chmod +x "$CURRENT_DIR/scripts/"*.sh

# Run installation (quiet mode if already installed)
# First run will show output, subsequent reloads will be silent
if [ -f "${HOME}/.claude/settings.json" ] && grep -q "claude-indicators" "${HOME}/.claude/settings.json" 2>/dev/null; then
    "$CURRENT_DIR/scripts/install.sh" --quiet
else
    "$CURRENT_DIR/scripts/install.sh"
fi

# Setup keybindings
# Only bind keys that are not empty (allows users to disable by setting to empty string)
setup_keybindings() {
    local key_enable=$(get_tmux_option "@claude-key-enable" "M-K")
    local key_disable=$(get_tmux_option "@claude-key-disable" "M-k")
    local key_clear=$(get_tmux_option "@claude-key-clear" "M-c")
    local key_clear_all=$(get_tmux_option "@claude-key-clear-all" "M-C")

    # Enable indicators
    if [ -n "$key_enable" ]; then
        tmux bind-key "$key_enable" run-shell "tmux set -g @claude-indicators-enabled on && '$CURRENT_DIR/bin/tmux-claude-indicators-on'"
    fi

    # Disable indicators
    if [ -n "$key_disable" ]; then
        tmux bind-key "$key_disable" run-shell "tmux set -g @claude-indicators-enabled off && '$CURRENT_DIR/bin/tmux-claude-cleanup-all' && tmux display-message 'Claude indicators disabled'"
    fi

    # Clear current window state
    if [ -n "$key_clear" ]; then
        tmux bind-key "$key_clear" run-shell "tmux set-window-option -t '#{window_id}' @claude-state 'active' && tmux set-window-option -t '#{window_id}' -u window-status-style && tmux display-message 'Claude state cleared'"
    fi

    # Clear all window states
    if [ -n "$key_clear_all" ]; then
        tmux bind-key "$key_clear_all" run-shell "'$CURRENT_DIR/bin/tmux-claude-cleanup-all'"
    fi
}

setup_keybindings
