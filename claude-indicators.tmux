#!/usr/bin/env bash
# tmux-claude-indicators - Visual state indicators for Claude Code in tmux
# TPM plugin entry point

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set default options if not already set
tmux set-option -gq @claude-indicators-enabled "on"
tmux set-option -gq @claude-indicators-debug "off"

# Animation settings
tmux set-option -gq @claude-indicators-interval "160"
tmux set-option -gq @claude-indicators-escalation "15"

# Emoji settings
tmux set-option -gq @claude-indicators-emoji-active "🫥"
tmux set-option -gq @claude-indicators-emoji-thinking "😜 🤪 😵‍💫"
tmux set-option -gq @claude-indicators-emoji-question "🔮"
tmux set-option -gq @claude-indicators-emoji-waiting "🫦"
tmux set-option -gq @claude-indicators-emoji-complete "✅"

# Color settings
tmux set-option -gq @claude-indicators-color-question "#b537f2"
tmux set-option -gq @claude-indicators-color-waiting "#9C0841"
tmux set-option -gq @claude-indicators-color-complete "#11dddd"

# Make scripts executable
chmod +x "$CURRENT_DIR/hooks/"*.sh
chmod +x "$CURRENT_DIR/bin/"*
chmod +x "$CURRENT_DIR/scripts/"*.sh

# Run installation
"$CURRENT_DIR/scripts/install.sh"
