# Session End & Stale Session Detector

## Overview

Detect when a Claude Code session has ended or become stale, and update the tmux window indicator accordingly. This solves the "ghost indicator" problem where a window permanently shows a stale emoji/color after the Claude process exits.

## Problem Statement

**Current behavior:** When a Claude Code process exits (user quits, crash, terminal close), the last emoji and color remain permanently stuck on the tmux window tab. A user with 8 windows might have 3 that show green checkmarks from sessions that ended hours ago.

**Desired behavior:** Dead sessions show a distinct "ended" indicator (greyed out). Stale sessions (no hook activity for a configurable duration) show a warning state.

## New States

| State | Emoji | Colour | Description |
|-------|-------|--------|-------------|
| ended | `💀` | colour240 (grey) bg, colour245 fg | Session terminated |
| stale | `⏳` | colour130 (amber) bg, colour255 fg | No activity for >5min |

These are additions to the existing 5 states (active, thinking, question, waiting, complete).

## Implementation Plan

### 1. New Hook: `SessionEnd` (`hooks/session-end.sh`)

Claude Code fires `SessionEnd` when a session terminates. The JSON input includes a `reason` field:
- `"clear"` - user cleared the session
- `"logout"` - user logged out
- `"prompt_input_exit"` - user typed exit/quit
- `"bypass_permissions_disabled"`
- `"other"` - unexpected termination

**The hook should:**
1. Kill any running animator/timer/flash processes for the pane
2. Set `@claude-state "ended"` on the window
3. Set `@claude-emoji` to a configurable ended emoji (default `💀`)
4. Set `window-status-style` to grey (colour240 bg, colour245 fg)
5. Set `@claude-timestamp` to current time
6. Unset `@claude-thinking-frame`

**Template (follows existing hook patterns):**

```bash
#!/usr/bin/env bash
# Claude Code SessionEnd hook - fires when session terminates
set -euo pipefail

cleanup() {
    [ -f "${PID_FILE:-}" ] && rm -f "$PID_FILE" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

if [ "$(tmux show -gv @claude-enabled 2>/dev/null)" != "on" ]; then
    cat > /dev/null
    exit 0
fi

TMUX_PANE="${TMUX_PANE:-}"
[ -z "$TMUX_PANE" ] && exit 0

hook_input=$(cat)

# Extract reason from JSON (no jq dependency)
reason="unknown"
if echo "$hook_input" | grep -qo '"reason":"[^"]*"'; then
    reason=$(echo "$hook_input" | grep -o '"reason":"[^"]*"' | head -1 | cut -d'"' -f4)
fi

# Kill animator if running
PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-animator-${TMUX_PANE}.pid"
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

# Set ended state
tmux set-window-option -t "$TMUX_PANE" @claude-state "ended" 2>/dev/null || true
tmux set-window-option -t "$TMUX_PANE" @claude-emoji "💀" 2>/dev/null || true
tmux set-window-option -t "$TMUX_PANE" @claude-timestamp "$(date +%s)" 2>/dev/null || true
tmux set-window-option -t "$TMUX_PANE" -u @claude-thinking-frame 2>/dev/null || true
tmux set-window-option -t "$TMUX_PANE" window-status-style "bg=colour240,fg=colour245" 2>/dev/null || true

exit 0
```

### 2. Stale Session Detector (`bin/claude-stale-detector`)

A background daemon started by `claude-code.tmux` (or `tmux-claude-code-on`) that polls all windows periodically and detects sessions that have gone stale.

**Logic:**
1. Run every 30 seconds (configurable via `@claude-stale-interval`, default 30)
2. For each window with a `@claude-state` set:
   - Read `@claude-timestamp`
   - If `(now - timestamp) > stale_threshold` AND state is `active` or `complete`, mark as stale
   - Do NOT mark `thinking`, `question`, `waiting` as stale (those are actively being handled)
   - Do NOT mark `ended` as stale (already dead)
3. When marking stale: set `@claude-state "stale"`, `@claude-emoji "⏳"`, amber background

**Stale threshold:** Configurable via `@claude-stale-timeout` (default: 300 seconds / 5 minutes).

**Process lifecycle:**
- Started by `tmux-claude-code-on` (or `claude-code.tmux`)
- PID tracked in `${TMUX_TMPDIR}/claude-stale-detector.pid` (global, not per-pane)
- Killed by `tmux-claude-code-cleanup-all`
- Uses `flock` like the animator to prevent duplicates

**Template:**

```bash
#!/usr/bin/env bash
# Stale session detector - polls windows and detects inactive sessions
set -euo pipefail

LOCK_FILE="${TMUX_TMPDIR:-/tmp}/claude-stale-detector.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    exit 0  # Another detector already running
fi

cleanup() { exec 200>&-; }
trap cleanup EXIT INT TERM

STALE_TIMEOUT=$(tmux show-option -gqv @claude-stale-timeout 2>/dev/null)
STALE_TIMEOUT=${STALE_TIMEOUT:-300}

POLL_INTERVAL=$(tmux show-option -gqv @claude-stale-interval 2>/dev/null)
POLL_INTERVAL=${POLL_INTERVAL:-30}

while true; do
    # Check if plugin still enabled
    [ "$(tmux show -gv @claude-enabled 2>/dev/null)" != "on" ] && exit 0

    now=$(date +%s)

    for pane_info in $(tmux list-panes -a -F '#{pane_id}|#{@claude-state}|#{@claude-timestamp}' 2>/dev/null); do
        pane_id=$(echo "$pane_info" | cut -d'|' -f1)
        state=$(echo "$pane_info" | cut -d'|' -f2)
        timestamp=$(echo "$pane_info" | cut -d'|' -f3)

        # Skip if no state, no timestamp, or already ended/stale
        [ -z "$state" ] || [ -z "$timestamp" ] && continue
        [ "$state" = "ended" ] || [ "$state" = "stale" ] && continue
        # Only mark active/complete as stale (thinking/question/waiting are active work)
        [ "$state" != "active" ] && [ "$state" != "complete" ] && continue

        elapsed=$((now - timestamp))
        if [ "$elapsed" -gt "$STALE_TIMEOUT" ]; then
            tmux set-window-option -t "$pane_id" @claude-state "stale" 2>/dev/null || true
            tmux set-window-option -t "$pane_id" @claude-emoji "⏳" 2>/dev/null || true
            tmux set-window-option -t "$pane_id" window-status-style "bg=colour130,fg=colour255" 2>/dev/null || true
        fi
    done

    sleep "$POLL_INTERVAL"
done
```

### 3. Update `SessionStart` Hook

When `SessionStart` fires with source `"resume"` or `"startup"`, it should clear any `ended` or `stale` state and return to `active`. The current `session-start.sh` already sets state to `active`, so this works automatically. No changes needed.

### 4. Update Format Strings (`bin/tmux-claude-code-on`)

Add `ended` and `stale` states to the nested conditionals in both `window-status-format` and `window-status-current-format`.

**New conditional chain (non-current):**
```
active    -> bg=colour54, fg=colour255, bold
thinking  -> bg=colour200, fg=colour255, bold
question  -> bg=colour128, fg=colour255, bold, blink
waiting   -> bg=colour33, fg=colour255, bold, blink
complete  -> bg=colour48, fg=colour232, bold
ended     -> bg=colour240, fg=colour245              <-- NEW
stale     -> bg=colour130, fg=colour255              <-- NEW
fallback  -> bg=colour130, fg=colour223, bold
```

The nesting will be 8 levels deep (was 6). This should be fine -- the existing 6-level nesting works reliably.

### 5. Register Hook in `scripts/install.sh`

Add `SessionEnd` to the Python hook injection script:

```python
hook_configs = {
    "SessionStart": f"{plugin_dir}/hooks/session-start.sh",
    "UserPromptSubmit": f"{plugin_dir}/hooks/user-prompt.sh",
    "PreToolUse": f"{plugin_dir}/hooks/user-prompt.sh",
    "Stop": f"{plugin_dir}/hooks/stop.sh",
    "Notification": f"{plugin_dir}/hooks/notification.sh",
    "SessionEnd": f"{plugin_dir}/hooks/session-end.sh",       # <-- NEW
}
```

### 6. Update `claude-code.tmux`

- Add default options:
  ```bash
  tmux set-option -gq @claude-emoji-ended "💀"
  tmux set-option -gq @claude-emoji-stale "⏳"
  tmux set-option -gq @claude-stale-timeout "300"    # 5 minutes
  tmux set-option -gq @claude-stale-interval "30"    # poll every 30s
  ```
- Make `hooks/session-end.sh` executable (already covered by `chmod +x "$CURRENT_DIR/hooks/"*.sh`)
- Make `bin/claude-stale-detector` executable

### 7. Update `bin/tmux-claude-code-cleanup-all`

Add cleanup for:
- Stale detector PID file: `${TMPDIR}/claude-stale-detector.pid`
- Kill stale detector process
- Clear `@claude-emoji` window option (currently not unset)
- Add `@claude-emoji` to the per-window unset loop

### 8. Start Stale Detector in `bin/tmux-claude-code-on`

After setting format strings, start the detector daemon:
```bash
STALE_DETECTOR="$CURRENT_DIR/bin/claude-stale-detector"
if [ -x "$STALE_DETECTOR" ]; then
    nohup "$STALE_DETECTOR" > /dev/null 2>&1 &
    echo $! > "${TMUX_TMPDIR:-/tmp}/claude-stale-detector.pid"
fi
```

## Files to Create

| File | Purpose |
|------|---------|
| `hooks/session-end.sh` | SessionEnd hook handler |
| `bin/claude-stale-detector` | Background stale session poller |

## Files to Modify

| File | Change |
|------|--------|
| `bin/tmux-claude-code-on` | Add ended/stale to format conditionals, start stale detector |
| `bin/tmux-claude-code-cleanup-all` | Kill stale detector, unset @claude-emoji |
| `scripts/install.sh` | Register SessionEnd hook |
| `claude-code.tmux` | Add default options for ended/stale emojis and timeouts |
| `README.md` | Document new states and configuration options |

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `@claude-emoji-ended` | `💀` | Emoji for terminated sessions |
| `@claude-emoji-stale` | `⏳` | Emoji for stale sessions |
| `@claude-stale-timeout` | `300` | Seconds before marking as stale |
| `@claude-stale-interval` | `30` | Polling interval for stale detector |

## State Machine Update

```
                    SessionStart
                         ↓
               ┌──── active (🤖) ◄──────────────┐
               │         ↓                       │
               │    UserPromptSubmit              │
               │         ↓                       │
               │    thinking (⠋⠙⠹⠸)             │
               │         ↓                       │
               │    Notification                  │
               │         ↓                       │
               │    question (🔮)                 │
               │         ↓ [15s]                  │
               │    waiting (🫦)                  │
               │         ↓ PreToolUse             │
               │    thinking ──► Stop ──► complete (✅)
               │                              │
               │         [5min timeout]        │ [5min timeout]
               │              ↓                ↓
               │         stale (⏳) ◄────── stale (⏳)
               │                              │
               │    SessionEnd                 │ SessionEnd
               │         ↓                     ↓
               └──── ended (💀) ◄──────── ended (💀)
                         ↓
                    SessionStart (resume)
                         ↓
                    active (🤖)
```

## Testing Checklist

- [ ] Start Claude Code session -> shows 🤖
- [ ] Exit Claude Code (`exit` or Ctrl+C) -> shows 💀 with grey background
- [ ] Leave a session idle for >5 minutes -> shows ⏳ with amber background
- [ ] Resume a session with `--resume` -> clears stale/ended, shows 🤖
- [ ] Multiple sessions: verify ended/stale only affects correct windows
- [ ] Stale detector doesn't mark thinking/question/waiting as stale
- [ ] `prefix + Alt+Shift+C` clears ended/stale states
- [ ] `prefix + Alt+K` (disable) stops stale detector
- [ ] No orphaned stale detector processes after disable/cleanup
