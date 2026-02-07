# Multi-Pane Awareness: Worst State + Count Badge

## Overview

When a tmux window has multiple panes running Claude Code, the window tab should show the most urgent state across all panes plus a count badge indicating how many Claude sessions exist. Single-pane windows look identical to today.

## Problem Statement

**Current behavior:** All hooks do `tmux set-window-option -t "$TMUX_PANE" @claude-state "thinking"`. When you pass a pane ID to `set-window-option`, tmux sets the option on the **window** containing that pane. With 3 Claude panes in one window, they all overwrite the same `@claude-state`. The last hook to fire wins -- the tab shows a random pane's state.

**Desired behavior:**

```
│ 3 api 🔮³ │    ← 3 Claude panes, most urgent is "question"
│ 5 web ⠹  │    ← 1 Claude pane, thinking (same as today)
│ 2 docs ✅² │   ← 2 Claude panes, both complete
```

The superscript count (²³⁴...) only appears when >1 Claude pane exists in the window.

## Design: Option A — "Worst State Wins" + Count Badge

**Priority order** (lower = more urgent, wins the tab display):

| Priority | State | Emoji |
|----------|-------|-------|
| 1 | waiting | 🫦 |
| 2 | question | 🔮 |
| 3 | thinking | ⠹ (animated) |
| 4 | active | 🤖 |
| 5 | complete | ✅ |
| 6 | stale | ⏳ |
| 7 | ended | 💀 |

If any pane is in "waiting", the whole tab shows waiting -- because that's the pane most urgently needing human attention.

## Architecture Change: Per-Pane State Tracking

### Current (window-level state)

```
Hook fires → set-window-option @claude-state → format string reads @claude-state
```

All panes overwrite the same variable. Last write wins.

### New (pane-level state + window-level aggregate)

```
Hook fires → set-option -p @claude-pane-state (pane-level)
           → call aggregator
           → aggregator reads all panes in window
           → sets @claude-state (worst), @claude-count, @claude-count-display (window-level)
           → format string reads window-level vars (unchanged)
```

**Requires tmux 3.0+** for pane options (`set-option -p`). User has tmux 3.5a. Document as minimum requirement.

## Implementation Plan

### 1. New Script: `bin/claude-aggregate-state`

Called by every hook after setting its own pane state. Reads all panes in the window, computes the worst state and count, and sets window-level display variables.

```bash
#!/usr/bin/env bash
# Aggregate per-pane Claude states into window-level display variables
# Usage: claude-aggregate-state <pane_id>
set -euo pipefail

PANE="${1:-$TMUX_PANE}"
[ -z "$PANE" ] && exit 1

# Get the window containing this pane
WINDOW=$(tmux display-message -t "$PANE" -p '#{window_id}' 2>/dev/null) || exit 1

# State priority (lower = more urgent)
state_priority() {
    case "$1" in
        waiting)  echo 1 ;;
        question) echo 2 ;;
        thinking) echo 3 ;;
        active)   echo 4 ;;
        complete) echo 5 ;;
        stale)    echo 6 ;;
        ended)    echo 7 ;;
        *)        echo 99 ;;
    esac
}

# Superscript digits for count badge
superscript() {
    local n="$1"
    local chars=("" "¹" "²" "³" "⁴" "⁵" "⁶" "⁷" "⁸" "⁹")
    if [ "$n" -le 9 ] 2>/dev/null; then
        echo "${chars[$n]}"
    else
        echo "⁺"  # 10+ panes, just show plus
    fi
}

# Read all pane states in this window
count=0
worst_priority=99
worst_state=""
worst_emoji=""
has_thinking=false

while IFS='|' read -r pane_id pane_state pane_emoji; do
    [ -z "$pane_state" ] && continue
    count=$((count + 1))

    if [ "$pane_state" = "thinking" ]; then
        has_thinking=true
    fi

    priority=$(state_priority "$pane_state")
    if [ "$priority" -lt "$worst_priority" ]; then
        worst_priority=$priority
        worst_state="$pane_state"
        worst_emoji="$pane_emoji"
    fi
done < <(tmux list-panes -t "$WINDOW" \
    -F '#{pane_id}|#{@claude-pane-state}|#{@claude-pane-emoji}' 2>/dev/null)

# If no Claude panes found, clear window state
if [ "$count" -eq 0 ]; then
    tmux set-window-option -t "$WINDOW" -u @claude-state 2>/dev/null || true
    tmux set-window-option -t "$WINDOW" -u @claude-emoji 2>/dev/null || true
    tmux set-window-option -t "$WINDOW" -u @claude-count 2>/dev/null || true
    tmux set-window-option -t "$WINDOW" -u @claude-count-display 2>/dev/null || true
    exit 0
fi

# Set window-level display variables
tmux set-window-option -t "$WINDOW" @claude-state "$worst_state" 2>/dev/null || true
tmux set-window-option -t "$WINDOW" @claude-count "$count" 2>/dev/null || true

# For thinking state, the emoji comes from @claude-thinking-frame (animated)
# For other states, set the emoji from the worst-state pane
if [ "$worst_state" != "thinking" ]; then
    tmux set-window-option -t "$WINDOW" @claude-emoji "$worst_emoji" 2>/dev/null || true
fi

# Set count badge (superscript, only when >1)
if [ "$count" -gt 1 ]; then
    tmux set-window-option -t "$WINDOW" @claude-count-display "$(superscript $count)" 2>/dev/null || true
else
    tmux set-window-option -t "$WINDOW" -u @claude-count-display 2>/dev/null || true
fi

# Handle animator lifecycle:
# If worst state is "thinking", ensure an animator is running for this window.
# If worst state is NOT "thinking" but some pane is still thinking,
# the animator is not needed (worst state takes priority in display).
ANIMATOR_PID_FILE="${TMUX_TMPDIR:-/tmp}/claude-animator-${WINDOW}.pid"

if [ "$worst_state" = "thinking" ]; then
    # Check if animator is already running for this window
    if [ -f "$ANIMATOR_PID_FILE" ]; then
        EXISTING_PID=$(cat "$ANIMATOR_PID_FILE" 2>/dev/null | head -1)
        if [ -n "$EXISTING_PID" ] && kill -0 "$EXISTING_PID" 2>/dev/null; then
            # Animator already running, nothing to do
            exit 0
        fi
    fi
    # Need to start animator - but this is handled by the calling hook
    # Just set the flag so the hook knows
    tmux set-window-option -t "$WINDOW" @claude-needs-animator "on" 2>/dev/null || true
else
    tmux set-window-option -t "$WINDOW" -u @claude-needs-animator 2>/dev/null || true
fi

exit 0
```

### 2. Modify All Hook Scripts

Every hook needs two changes:

**a) Store state at pane level (in addition to window level)**

Before (in every hook):
```bash
tmux set-window-option -t "$TMUX_PANE" @claude-state "thinking"
tmux set-window-option -t "$TMUX_PANE" @claude-emoji "⠹"
```

After:
```bash
# Set per-pane state (pane option, survives aggregation)
tmux set-option -p -t "$TMUX_PANE" @claude-pane-state "thinking" 2>/dev/null || true
tmux set-option -p -t "$TMUX_PANE" @claude-pane-emoji "⠹" 2>/dev/null || true

# Aggregate all panes and update window display
"$SCRIPT_DIR/bin/claude-aggregate-state" "$TMUX_PANE"
```

**b) Get SCRIPT_DIR in hooks that don't have it**

`session-start.sh` and `stop.sh` don't currently resolve `SCRIPT_DIR`. Add:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
```

### Files to modify (hook changes):

#### `hooks/session-start.sh`
```bash
# Add SCRIPT_DIR resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Replace:
tmux set-window-option -t "$TMUX_PANE" @claude-state "active"
tmux set-window-option -t "$TMUX_PANE" @claude-emoji "🤖"

# With:
tmux set-option -p -t "$TMUX_PANE" @claude-pane-state "active" 2>/dev/null || true
tmux set-option -p -t "$TMUX_PANE" @claude-pane-emoji "🤖" 2>/dev/null || true
"$SCRIPT_DIR/bin/claude-aggregate-state" "$TMUX_PANE"
```

Keep the `window-status-style` set — the aggregator doesn't handle that (it only sets state/emoji/count). The hook with the worst-priority state will end up being the last one to set `window-status-style` anyway, which is acceptable for v1.

#### `hooks/user-prompt.sh`
```bash
# Replace:
tmux set-window-option -t "$TMUX_PANE" @claude-state "thinking"
tmux set-window-option -t "$TMUX_PANE" @claude-thinking-frame "😜"

# With:
tmux set-option -p -t "$TMUX_PANE" @claude-pane-state "thinking" 2>/dev/null || true
tmux set-option -p -t "$TMUX_PANE" @claude-pane-emoji "⠹" 2>/dev/null || true
"$SCRIPT_DIR/bin/claude-aggregate-state" "$TMUX_PANE"
```

**Animator change:** Currently the animator targets a pane. With multi-pane, we need the animator to update the **window-level** `@claude-thinking-frame` only when the aggregated worst state is "thinking". The simplest approach for v1: keep the animator as-is (it checks `@claude-state` which is now the aggregated state). If the worst state is no longer "thinking" (because another pane escalated to question), the animator stops. When the question is resolved and worst state returns to thinking, the next `user-prompt.sh` or `PreToolUse` hook from the thinking pane will re-trigger aggregation, and the aggregator sets `@claude-needs-animator`. The calling hook can check this flag and restart the animator.

#### `hooks/stop.sh`
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Replace:
tmux set-window-option -t "$TMUX_PANE" @claude-state "complete"
tmux set-window-option -t "$TMUX_PANE" @claude-emoji "✅"

# With:
tmux set-option -p -t "$TMUX_PANE" @claude-pane-state "complete" 2>/dev/null || true
tmux set-option -p -t "$TMUX_PANE" @claude-pane-emoji "✅" 2>/dev/null || true
"$SCRIPT_DIR/bin/claude-aggregate-state" "$TMUX_PANE"
```

#### `hooks/notification.sh`
```bash
# In the permission_prompt branch:
tmux set-option -p -t "$TMUX_PANE" @claude-pane-state "question" 2>/dev/null || true
tmux set-option -p -t "$TMUX_PANE" @claude-pane-emoji "🔮" 2>/dev/null || true
"$SCRIPT_DIR/bin/claude-aggregate-state" "$TMUX_PANE"

# In the escalation timer (15s):
tmux set-option -p -t "$TMUX_PANE" @claude-pane-state "waiting" 2>/dev/null || true
tmux set-option -p -t "$TMUX_PANE" @claude-pane-emoji "🫦" 2>/dev/null || true
"$SCRIPT_DIR/bin/claude-aggregate-state" "$TMUX_PANE"

# In the idle_prompt branch:
tmux set-option -p -t "$TMUX_PANE" @claude-pane-state "active" 2>/dev/null || true
tmux set-option -p -t "$TMUX_PANE" @claude-pane-emoji "🤖" 2>/dev/null || true
"$SCRIPT_DIR/bin/claude-aggregate-state" "$TMUX_PANE"
```

### 3. Update Format Strings (`bin/tmux-claude-code-on`)

Add the count badge after the emoji. The count display is stored in `@claude-count-display` (a pre-formatted superscript string, or empty if count=1).

**Current format (emoji portion):**
```
#{?#{==:#{@claude-state},thinking},#{@claude-thinking-frame},#{@claude-emoji}}
```

**New format (add count badge):**
```
#{?#{==:#{@claude-state},thinking},#{@claude-thinking-frame},#{@claude-emoji}}#{@claude-count-display}
```

That's it — `@claude-count-display` is empty for single-pane windows (unset), so nothing changes for the common case. For multi-pane, it shows `²`, `³`, etc.

### 4. Update `bin/tmux-claude-code-cleanup-all`

Add cleanup for pane-level options:

```bash
# In the per-window cleanup loop, also clean pane options
for pane_id in $(tmux list-panes -a -F "#{pane_id}" 2>/dev/null); do
    tmux set-option -p -t "$pane_id" -u @claude-pane-state 2>/dev/null || true
    tmux set-option -p -t "$pane_id" -u @claude-pane-emoji 2>/dev/null || true
done

# In the per-window cleanup, add new variables
tmux set-window-option -t "$win_id" -u @claude-count 2>/dev/null || true
tmux set-window-option -t "$win_id" -u @claude-count-display 2>/dev/null || true
tmux set-window-option -t "$win_id" -u @claude-needs-animator 2>/dev/null || true
tmux set-window-option -t "$win_id" -u @claude-emoji 2>/dev/null || true
```

### 5. Handle Pane Close / Claude Exit

When a Claude process exits and the `SessionEnd` hook fires (from the session-end-stale-detector feature), it should:

1. Set `@claude-pane-state "ended"` on the pane
2. Call the aggregator to recompute the window display

If a pane is destroyed entirely (e.g., user closes it), tmux automatically removes pane options. But the window-level aggregate won't update until the next hook fires from a remaining pane. For v1 this is acceptable — the count will be off until the next state change. A future enhancement could use tmux's `pane-exited` hook (tmux 3.2+) to trigger re-aggregation.

### 6. Backward Compatibility

- **Single pane windows:** `@claude-count-display` is unset (empty), so the format string shows exactly what it shows today. Zero visual change.
- **tmux < 3.0:** `set-option -p` will fail silently (the `2>/dev/null || true` catches it). The aggregator won't find pane states, so it falls back to clearing window state. The old behavior (last-write-wins) remains as a degraded mode. Document tmux 3.0+ as recommended.

## Files to Create

| File | Purpose |
|------|---------|
| `bin/claude-aggregate-state` | Aggregates per-pane states into window-level display |

## Files to Modify

| File | Change |
|------|--------|
| `hooks/session-start.sh` | Add SCRIPT_DIR, set pane option, call aggregator |
| `hooks/user-prompt.sh` | Set pane option, call aggregator |
| `hooks/stop.sh` | Add SCRIPT_DIR, set pane option, call aggregator |
| `hooks/notification.sh` | Set pane option in all branches, call aggregator |
| `bin/tmux-claude-code-on` | Append `#{@claude-count-display}` to format strings |
| `bin/tmux-claude-code-cleanup-all` | Clean up pane options and new window variables |

## Superscript Count Reference

| Count | Display | Notes |
|-------|---------|-------|
| 1 | *(nothing)* | Single pane, identical to today |
| 2 | ² | |
| 3 | ³ | |
| 4 | ⁴ | |
| 5 | ⁵ | |
| 6 | ⁶ | |
| 7 | ⁷ | |
| 8 | ⁸ | |
| 9 | ⁹ | |
| 10+ | ⁺ | Edge case, unlikely |

Unicode superscript digits: `¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹`
All are single-width characters — no layout bounce.

## Edge Cases

### Pane has Claude but no hooks have fired yet
No `@claude-pane-state` set → aggregator skips it → not counted. This is correct — until SessionStart fires, we don't know Claude is running.

### All Claude panes close, non-Claude panes remain
Aggregator finds 0 Claude panes → unsets all window-level `@claude-*` variables → window tab falls back to the "no claude" style (rust brown, `colour130`).

### Pane destroyed while in thinking state
Animator checks `@claude-state` (window-level aggregate). If the destroyed pane was the only thinking pane and another pane is in "active", the aggregate flips to "active" on next aggregation. But aggregation only happens when a hook fires. For v1, the tab might show a stale "thinking" state until another hook fires. The stale detector (separate feature) would eventually catch this.

### Two panes both thinking
Both fire `user-prompt.sh`, both call the aggregator. The aggregator sees worst state = "thinking", count = 2. Tab shows `⠹²`. Only one animator runs (keyed by window, not pane). This is correct — one animation serves the whole tab.

### Race condition: two hooks fire simultaneously
The aggregator is fast (<10ms) and sets atomic window options. Even if two aggregators overlap, they'll both compute the same result (reading the same pane states). No locking needed for v1.

## Visual Examples

```
Single pane (unchanged from today):
│ 1 frontend ⠹ │ 2 api 🤖 │ 3 docs ✅ │

Multi-pane windows:
│ 1 frontend ⠹³ │ 2 api 🔮² │ 3 docs ✅⁴ │
   ↑ 3 thinking    ↑ 2 panes,     ↑ 4 panes,
                     1 question      all complete

Mixed urgency (worst wins):
│ 1 dev 🔮³ │   ← 3 panes: 1 question + 1 thinking + 1 active
                   question is most urgent → shows 🔮
                   count ³ tells you there are 3 Claude sessions total
```

## Future Enhancements (not in v1)

- **Pane border integration (Option D):** Show per-pane state in `pane-border-format` when inside the window. Natural "drill down" from tab overview to per-pane detail.
- **Per-pane count breakdown:** Instead of just total count, show `2⠹1🔮` (2 thinking, 1 question). Requires more tab space.
- **`pane-exited` hook:** Auto-reaggregate when a pane is destroyed (tmux 3.2+).
- **Window-level animator keying:** Move animator PID tracking from pane-based to window-based for cleaner lifecycle management.

## Testing Checklist

- [ ] Single pane window: looks identical to today (no count badge)
- [ ] 2 panes, same state: shows emoji + ² (e.g., `🤖²`)
- [ ] 2 panes, different states: shows most urgent state + ² (e.g., `🔮²`)
- [ ] 3+ panes: correct superscript count
- [ ] Pane transitions: count badge updates when pane state changes
- [ ] Close Claude in one pane: count decrements on next hook fire
- [ ] Close all Claude panes: falls back to "no claude" style
- [ ] Thinking animation works with multi-pane (animator runs for window)
- [ ] Question/waiting escalation works per-pane (doesn't affect other panes)
- [ ] `prefix + Alt+Shift+C` cleanup clears pane options and window variables
- [ ] tmux < 3.0 degrades gracefully (last-write-wins, no count badge)
