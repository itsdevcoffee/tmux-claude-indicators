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

# Color settings - Cyberpunk/TRON aesthetic
tmux set-option -gq @claude-indicators-color-active-bg "#A78BFA"      # Soft lavender
tmux set-option -gq @claude-indicators-color-active-fg "#1a0a2e"      # Dark purple
tmux set-option -gq @claude-indicators-color-thinking-bg "#F706CF"    # Hot pink
tmux set-option -gq @claude-indicators-color-thinking-fg "#FFFFFF"    # White
tmux set-option -gq @claude-indicators-color-question-bg "#791E94"    # Deep violet
tmux set-option -gq @claude-indicators-color-question-fg "#FFFFFF"    # White
tmux set-option -gq @claude-indicators-color-waiting-bg "#035EE8"     # Laser blue
tmux set-option -gq @claude-indicators-color-waiting-fg "#FFFFFF"     # White
tmux set-option -gq @claude-indicators-color-complete-bg "#02F78E"    # Matrix green
tmux set-option -gq @claude-indicators-color-complete-fg "#000000"    # Black

# Make scripts executable
chmod +x "$CURRENT_DIR/hooks/"*.sh
chmod +x "$CURRENT_DIR/bin/"*
chmod +x "$CURRENT_DIR/scripts/"*.sh

# Run installation
"$CURRENT_DIR/scripts/install.sh"
