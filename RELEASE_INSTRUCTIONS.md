# Release Instructions for tmux-claude-code v1.0.1

## Context
This is the tmux-claude-code plugin - production-ready after fixing all critical bugs from a comprehensive audit.

**Current Status:**
- ✅ All code fixes completed and committed
- ✅ Git tag v1.0.1 created and pushed
- ⏳ Need to create GitHub release
- ⏳ Need to test TPM installation

## Task 1: Create GitHub Release

Use the GitHub CLI to create the release:

```bash
gh release create v1.0.1 \
  --title "v1.0.1 - Production Ready Release" \
  --notes "$(cat <<'EOF'
## 🎉 tmux-claude-code v1.0.1

Production-ready release with all critical bug fixes from comprehensive security audit.

### ✅ Critical Fixes

- **Fixed broken PID validation** - Now uses `kill -0` to properly check if processes exist
- **Fixed race condition** - Atomic PID file creation prevents duplicate animators
- **Fixed unquoted variables** - All variable expansions properly quoted for security

### 🛡️ Security & Reliability

- Atomic file writes for settings.json (prevents corruption)
- Error handling for critical tmux commands
- Trap handlers ensure cleanup on exit/crash/interrupt
- Bash safety with `set -euo pipefail`
- Multi-user tmux server support via `TMUX_TMPDIR`

### 📦 Installation

Via TPM (recommended):
\`\`\`tmux
set -g @plugin 'itsdevcoffee/tmux-claude-code'
\`\`\`

Then press \`prefix + I\` to install.

### 🎨 Features

- **🫥 Active** - Claude idle, ready for input
- **😜🤪😵‍💫 Thinking** - Animated while processing
- **🔮 Question** - Needs permission (purple background)
- **🫦 Waiting** - Question unanswered >15s (magenta background)
- **✅ Complete** - Task finished (teal flash)

### 📚 Documentation

See [README.md](https://github.com/itsdevcoffee/tmux-claude-code/blob/main/README.md) for full documentation.

### 🙏 Credits

Audit feedback helped identify and fix critical bugs before production release.
EOF
)"
```

**If gh CLI has permission issues:**
- Run: `gh auth refresh -h github.com -s workflow`
- Or create release manually at: https://github.com/itsdevcoffee/tmux-claude-code/releases/new

## Task 2: Test TPM Installation

### Step 1: Add Plugin to tmux.conf

Add this line to `~/.tmux.conf` or `~/.tmux.conf.local`:

```tmux
set -g @plugin 'itsdevcoffee/tmux-claude-code'
```

### Step 2: Install via TPM

```bash
# Press in tmux:
# prefix + I (that's Shift+i)

# Or manually:
~/.tmux/plugins/tpm/bin/install_plugins
```

### Step 3: Verify Installation

Check that files were installed:

```bash
ls -la ~/.tmux/plugins/tmux-claude-code/
```

Should see:
- `bin/`
- `hooks/`
- `scripts/`
- `claude-code.tmux`
- `README.md`
- `LICENSE`

### Step 4: Check Hook Installation

Verify hooks were added to Claude Code settings:

```bash
cat ~/.claude/settings.json | grep tmux-claude-code
```

Should see hook paths pointing to the plugin directory.

### Step 5: Enable Indicators

In tmux, press: `Ctrl-a K` (or your prefix + K)

Should see: "Claude indicators enabled"

### Step 6: Test Functionality

1. Start a Claude Code session in a tmux window
2. Submit a prompt
3. Watch the status bar - should see:
   - 🫥 → 😜 (thinking animation) → ✅ (complete with teal flash)

### Step 7: Test Cleanup

```bash
# Check for running animators
pgrep -f claude-thinking-animator

# Should show 1 process while thinking
# Should be empty after complete

# Check PID files
ls ${TMUX_TMPDIR:-/tmp}/claude-*.pid

# Should only exist while processes are running
```

## Expected Results

✅ **Success Criteria:**
- GitHub release created successfully
- TPM installs plugin to `~/.tmux/plugins/`
- Hooks auto-injected into `~/.claude/settings.json`
- Indicators show correctly in tmux status bar
- Animations work (thinking emoji cycles)
- No orphaned processes after completion
- PID files cleaned up properly

❌ **Failure Scenarios:**
- If hooks don't auto-inject, check if Python is available
- If indicators don't show, press `prefix + K` to enable
- If animators accumulate, check PID validation fix is in place

## Troubleshooting

**Indicators not showing:**
```bash
# Check if enabled
tmux show -gv @claude-enabled
# Should output: on

# Enable manually
tmux set -g @claude-enabled on
~/.tmux/plugins/tmux-claude-code/bin/tmux-claude-code-on
```

**Multiple animators running:**
```bash
# Should only show 1 per thinking window
pgrep -f claude-thinking-animator | wc -l

# If more than expected:
pkill -f claude-thinking-animator
rm ${TMUX_TMPDIR:-/tmp}/claude-animator-*.pid
```

## Verification Checklist

After testing, verify:
- [ ] GitHub release exists at https://github.com/itsdevcoffee/tmux-claude-code/releases
- [ ] Release shows v1.0.1 tag
- [ ] Release notes are complete
- [ ] TPM installation works
- [ ] Hooks are injected automatically
- [ ] All 5 states work (active, thinking, question, waiting, complete)
- [ ] Animation cycles smoothly
- [ ] No process leaks after 10+ prompts
- [ ] PID files are cleaned up
- [ ] Enable/disable toggle works

## Report Back

Please confirm:
1. GitHub release URL
2. TPM installation success/failure
3. Any issues encountered
4. Test results for all 5 indicator states
