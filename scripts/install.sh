#!/usr/bin/env bash
# Installation script for tmux-claude-indicators

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS_FILE="${HOME}/.claude/settings.json"
SETTINGS_BACKUP="${HOME}/.claude/settings.json.backup-$(date +%Y%m%d-%H%M%S)"

# Parse arguments
QUIET=false
if [ "$1" = "--quiet" ] || [ "$1" = "-q" ]; then
    QUIET=true
fi

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Logging functions
log() {
    if [ "$QUIET" = false ]; then
        log "$@"
    fi
}

log_always() {
    log "$@"
}

log "🎨 Installing tmux-claude-indicators..."

# Check dependencies
if ! command -v tmux >/dev/null 2>&1; then
    log -e "${RED}✗ Error: tmux not found${NC}"
    log "  Please install tmux first"
    exit 1
fi

if ! command -v clod >/dev/null 2>&1; then
    log -e "${YELLOW}⚠ Warning: Claude Code (clod) not found${NC}"
    log "  Install from: https://claude.ai/download"
    log "  Continuing anyway (you can install Claude Code later)..."
fi

# Check if running in tmux
if [ -z "$TMUX" ]; then
    log -e "${YELLOW}⚠ Not running in tmux session${NC}"
    log "  Plugin will be configured, but indicators won't work until you're in tmux"
fi

# Create Claude Code config directory if it doesn't exist
mkdir -p "${HOME}/.claude"

# Backup existing settings if they exist
if [ -f "$SETTINGS_FILE" ]; then
    log "📦 Backing up existing settings to: ${SETTINGS_BACKUP}"
    cp "$SETTINGS_FILE" "$SETTINGS_BACKUP"
else
    log "📝 Creating new settings.json"
    echo '{}' > "$SETTINGS_FILE"
fi

# Inject hooks into settings.json
log "🔗 Injecting Claude Code hooks..."

# Use Python for reliable JSON manipulation (fallback to manual if Python not available)
if command -v python3 >/dev/null 2>&1; then
    python3 - "$SETTINGS_FILE" "$PLUGIN_DIR" <<'EOF'
import json
import sys

settings_file = sys.argv[1]
plugin_dir = sys.argv[2]

# Read existing settings
with open(settings_file, 'r') as f:
    settings = json.load(f)

# Ensure hooks object exists
if 'hooks' not in settings:
    settings['hooks'] = {}

# Define hook configurations
hook_configs = {
    "SessionStart": f"{plugin_dir}/hooks/session-start.sh",
    "UserPromptSubmit": f"{plugin_dir}/hooks/user-prompt.sh",
    "PreToolUse": f"{plugin_dir}/hooks/user-prompt.sh",  # Same as UserPromptSubmit
    "Stop": f"{plugin_dir}/hooks/stop.sh",
    "Notification": f"{plugin_dir}/hooks/notification.sh"
}

# Inject each hook (preserve existing hooks)
for event, command in hook_configs.items():
    if event not in settings['hooks']:
        settings['hooks'][event] = []

    # Check if our hook already exists
    hook_exists = any(
        h.get('hooks', [{}])[0].get('command', '').startswith(plugin_dir)
        for h in settings['hooks'][event]
        if isinstance(h, dict) and 'hooks' in h
    )

    if not hook_exists:
        settings['hooks'][event].append({
            "hooks": [{
                "type": "command",
                "command": command,
                "timeout": 5000
            }]
        })

# Write updated settings atomically (prevent corruption)
import os
import tempfile

# Write to temporary file first
temp_fd, temp_path = tempfile.mkstemp(dir=os.path.dirname(settings_file), prefix='.settings.json.tmp')
try:
    with os.fdopen(temp_fd, 'w') as f:
        json.dump(settings, f, indent=2)
    # Atomic rename (POSIX guarantees atomicity)
    os.rename(temp_path, settings_file)
    print("✓ Hooks injected successfully")
except Exception as e:
    # Clean up temp file on error
    if os.path.exists(temp_path):
        os.unlink(temp_path)
    raise
EOF
else
    log -e "${YELLOW}⚠ Python not found - hooks not auto-configured${NC}"
    log "  Please manually add hooks to ~/.claude/settings.json"
    log "  See: ${PLUGIN_DIR}/config/example-settings.json"
fi

# Apply tmux format strings (only if in tmux)
if [ -n "$TMUX" ]; then
    log "🎨 Applying tmux status bar formats..."
    "$PLUGIN_DIR/bin/tmux-claude-indicators-on"

    # Enable indicators by default
    tmux set -g @claude-indicators-enabled on

    log -e "${GREEN}✓ Installation complete!${NC}"
    log ""
    log "🎉 Claude Code indicators are now active!"
    log ""
    log "Controls:"
    log "  Ctrl-a K        Enable indicators"
    log "  Ctrl-a Alt-k    Disable indicators"
    log "  Ctrl-a C        Clear current window state"
    log "  Ctrl-a Alt-c    Clear all window states"
    log ""
    log "States:"
    log "  🫥  Active (waiting for input)"
    log "  😜🤪😵‍💫  Thinking (animated)"
    log "  🔮  Question (needs permission)"
    log "  🫦  Waiting (question unanswered >15s)"
    log "  ✅  Complete (task finished)"
    log ""
    log "Note: Restart Claude Code sessions to load hooks"
else
    log -e "${GREEN}✓ Configuration complete!${NC}"
    log "  Start a tmux session and press Ctrl-a K to enable indicators"
fi
