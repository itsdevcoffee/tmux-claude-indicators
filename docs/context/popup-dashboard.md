# Popup Dashboard (prefix + J)

## Overview

A keybinding (`prefix + J`) opens a tmux `display-popup` showing a live summary of all Claude sessions across all windows with their current state, working directory, and elapsed time. The user can select a session to jump to it instantly.

## Problem Statement

**Current behavior:** To find which Claude sessions need attention, users must visually scan every window tab in the status bar. With 8+ windows, this is slow and error-prone.

**Desired behavior:** One keystroke shows a formatted table of all sessions. Selecting a row jumps to that window. Sessions needing attention are highlighted and sorted to the top.

## Preview

```
╭───────────────────────────────────────────────────────────────╮
│  Claude Code Sessions                                         │
│                                                               │
│  # │ Window       │ State     │ Elapsed │ Directory           │
│ ───┼──────────────┼───────────┼─────────┼──────────────────── │
│  2 │ api-server   │ QUESTION  │   1m45s │ ~/projects/api      │
│  4 │ docs         │ WAITING   │   3m12s │ ~/projects/docs     │
│  1 │ frontend     │ thinking  │     32s │ ~/projects/web      │
│  3 │ backend      │ active    │   8m04s │ ~/projects/backend  │
│  5 │ infra        │ complete  │     12s │ ~/projects/terraform│
│  6 │ tests        │ ended     │  22m31s │ ~/projects/tests    │
│                                                               │
│  [Enter] Jump  [Esc] Close  [q] Quit                          │
╰───────────────────────────────────────────────────────────────╯
```

Sessions needing attention (question, waiting) are sorted to top and highlighted.

## Dependencies

- **tmux 3.2+** - required for `display-popup` (fallback: `display-message` summary for older versions)
- **fzf** (optional) - enables fuzzy filtering and selection. Without fzf, uses a numbered menu via `select` or plain list

## Implementation Plan

### 1. New Script: `bin/claude-dashboard`

The core script that gathers data and presents the dashboard.

**Data gathering:**

```bash
# Get all windows with claude state info
tmux list-windows -F '#{window_index}|#{window_name}|#{@claude-state}|#{@claude-timestamp}|#{pane_current_path}' 2>/dev/null
```

Each field:
- `#{window_index}` - window number for `select-window`
- `#{window_name}` - display name
- `#{@claude-state}` - current state (active/thinking/question/waiting/complete/ended/stale or empty)
- `#{@claude-timestamp}` - Unix epoch of last state change
- `#{pane_current_path}` - working directory of the active pane

**Elapsed time calculation:**

```bash
format_elapsed() {
    local ts="$1"
    [ -z "$ts" ] && echo "—" && return
    local now=$(date +%s)
    local elapsed=$((now - ts))
    if [ $elapsed -lt 60 ]; then
        echo "${elapsed}s"
    elif [ $elapsed -lt 3600 ]; then
        echo "$((elapsed / 60))m$((elapsed % 60))s"
    else
        echo "$((elapsed / 3600))h$((elapsed % 3600 / 60))m"
    fi
}
```

**Sort order priority:**
1. `waiting` (longest first - most urgent)
2. `question` (longest first)
3. `thinking` (longest first)
4. `active` (longest first)
5. `complete`
6. `stale`
7. `ended`
8. Windows with no claude state (skip or show at bottom)

**Output with fzf:**

```bash
# Pipe formatted lines into fzf
selected=$(echo "$formatted_output" | fzf \
    --ansi \
    --header="Claude Code Sessions" \
    --prompt="Jump to > " \
    --no-sort \
    --reverse \
    --border=rounded \
    --info=hidden \
    --pointer="▶" \
    --color="header:bold,pointer:200,prompt:200" \
    --preview-window=hidden)

# Extract window index from selected line and jump
if [ -n "$selected" ]; then
    win_idx=$(echo "$selected" | awk '{print $1}')
    tmux select-window -t ":${win_idx}"
fi
```

**Fallback without fzf:**

```bash
# Display numbered list, read selection
echo "$formatted_output"
echo ""
read -p "Jump to window # (or Enter to cancel): " choice
if [ -n "$choice" ]; then
    tmux select-window -t ":${choice}"
fi
```

**ANSI color coding for states (in fzf mode):**

```bash
# Color codes for terminal output (not tmux format strings)
case "$state" in
    question) color="\033[1;35m" ;;    # bold magenta
    waiting)  color="\033[1;34m" ;;    # bold blue
    thinking) color="\033[1;35m" ;;    # bold pink (closest)
    active)   color="\033[0;37m" ;;    # white
    complete) color="\033[1;32m" ;;    # bold green
    ended)    color="\033[0;90m" ;;    # grey
    stale)    color="\033[0;33m" ;;    # yellow/amber
    *)        color="\033[0;90m" ;;    # grey for no state
esac
```

**State labels for display:**

```bash
case "$state" in
    question) label="QUESTION" ;;   # uppercase = needs attention
    waiting)  label="WAITING" ;;
    thinking) label="thinking" ;;
    active)   label="active" ;;
    complete) label="complete" ;;
    ended)    label="ended" ;;
    stale)    label="stale" ;;
    *)        label="—" ;;
esac
```

**Full script template:**

```bash
#!/usr/bin/env bash
# Claude Code Dashboard - shows all sessions with state and elapsed time
set -euo pipefail

# State sort priority (lower = more urgent)
state_priority() {
    case "$1" in
        waiting)  echo 1 ;;
        question) echo 2 ;;
        thinking) echo 3 ;;
        active)   echo 4 ;;
        complete) echo 5 ;;
        stale)    echo 6 ;;
        ended)    echo 7 ;;
        *)        echo 8 ;;
    esac
}

format_elapsed() {
    local ts="$1"
    [ -z "$ts" ] && echo "—" && return
    local now=$(date +%s)
    local elapsed=$((now - ts))
    if [ $elapsed -lt 0 ]; then
        echo "—"
    elif [ $elapsed -lt 60 ]; then
        printf "%ds" "$elapsed"
    elif [ $elapsed -lt 3600 ]; then
        printf "%dm%02ds" "$((elapsed / 60))" "$((elapsed % 60))"
    else
        printf "%dh%02dm" "$((elapsed / 3600))" "$((elapsed % 3600 / 60))"
    fi
}

state_color() {
    case "$1" in
        question) printf "\033[1;35m" ;;
        waiting)  printf "\033[1;34m" ;;
        thinking) printf "\033[1;95m" ;;
        active)   printf "\033[0;37m" ;;
        complete) printf "\033[1;32m" ;;
        ended)    printf "\033[0;90m" ;;
        stale)    printf "\033[0;33m" ;;
        *)        printf "\033[0;90m" ;;
    esac
}

state_label() {
    case "$1" in
        question) echo "QUESTION" ;;
        waiting)  echo "WAITING" ;;
        thinking) echo "thinking" ;;
        active)   echo "active" ;;
        complete) echo "complete" ;;
        ended)    echo "ended" ;;
        stale)    echo "stale" ;;
        *)        echo "—" ;;
    esac
}

RESET="\033[0m"

# Check for cross-session mode
ALL_SESSIONS=$(tmux show-option -gqv @claude-dashboard-all-sessions 2>/dev/null)
if [ "$ALL_SESSIONS" = "on" ]; then
    LIST_CMD="tmux list-windows -a"
else
    LIST_CMD="tmux list-windows"
fi

# Gather window data
lines=""
while IFS='|' read -r idx name state timestamp path; do
    [ -z "$state" ] && continue  # Skip windows without claude state

    elapsed=$(format_elapsed "$timestamp")
    priority=$(state_priority "$state")
    color=$(state_color "$state")
    label=$(state_label "$state")

    # Shorten path (replace $HOME with ~)
    short_path="${path/#$HOME/\~}"
    # Truncate long paths
    if [ ${#short_path} -gt 30 ]; then
        short_path="...${short_path: -27}"
    fi

    # Format: priority|index|formatted_line
    line=$(printf "%s|%s|${color}%3s  %-14s  %-9s  %7s  %s${RESET}" \
        "$priority" "$idx" "$idx" "$name" "$label" "$elapsed" "$short_path")
    lines="${lines}${line}\n"
done < <($LIST_CMD -F '#{window_index}|#{window_name}|#{@claude-state}|#{@claude-timestamp}|#{pane_current_path}' 2>/dev/null)

if [ -z "$lines" ]; then
    echo "No Claude Code sessions found."
    read -n1 -p "Press any key to close..."
    exit 0
fi

# Sort by priority (urgent first), then by window index
sorted=$(printf "%b" "$lines" | sort -t'|' -k1,1n -k2,2n | cut -d'|' -f3-)

# Header
header=$(printf "  %3s  %-14s  %-9s  %7s  %s" "#" "Window" "State" "Elapsed" "Directory")

# Use fzf if available
if command -v fzf >/dev/null 2>&1; then
    selected=$(printf "%b" "$sorted" | fzf \
        --ansi \
        --header="$header" \
        --prompt="Jump to > " \
        --no-sort \
        --reverse \
        --info=hidden \
        --pointer="▶" \
        --color="header:bold,pointer:200,prompt:200,hl:200,hl+:200" \
        --bind="q:abort" \
        --expect="enter" 2>/dev/null) || exit 0

    # fzf --expect outputs key on first line, selection on second
    key=$(echo "$selected" | head -1)
    choice=$(echo "$selected" | tail -1)

    if [ -n "$choice" ]; then
        win_idx=$(echo "$choice" | awk '{print $1}')
        tmux select-window -t ":${win_idx}" 2>/dev/null
    fi
else
    # Fallback: simple numbered display
    echo "$header"
    echo "  ───  ──────────────  ─────────  ───────  ────────────────────"
    printf "%b\n" "$sorted"
    echo ""
    read -p "Jump to window # (Enter to cancel): " choice
    if [ -n "$choice" ]; then
        tmux select-window -t ":${choice}" 2>/dev/null
    fi
fi
```

### 2. Keybinding Setup in `claude-code.tmux`

Add default option and keybinding:

```bash
# In claude-code.tmux defaults
tmux set-option -gq @claude-key-dashboard "M-j"   # Alt+J (lowercase)
tmux set-option -gq @claude-dashboard-all-sessions "off"

# In setup_keybindings()
local key_dashboard=$(get_tmux_option "@claude-key-dashboard" "M-j")

if [ -n "$key_dashboard" ]; then
    tmux bind-key "$key_dashboard" display-popup -E -w 80% -h 50% \
        "'$CURRENT_DIR/bin/claude-dashboard'"
fi
```

### 3. Fallback for tmux < 3.2

`display-popup` requires tmux 3.2+. For older versions, fall back to opening a temporary window:

```bash
# In setup_keybindings(), detect tmux version
tmux_version=$(tmux -V | grep -oE '[0-9]+\.[0-9]+')
if [ "$(echo "$tmux_version >= 3.2" | bc 2>/dev/null)" = "1" ]; then
    tmux bind-key "$key_dashboard" display-popup -E -w 80% -h 50% \
        "'$CURRENT_DIR/bin/claude-dashboard'"
else
    tmux bind-key "$key_dashboard" new-window -n "claude-dash" \
        "'$CURRENT_DIR/bin/claude-dashboard'; exit"
fi
```

## Files to Create

| File | Purpose |
|------|---------|
| `bin/claude-dashboard` | Dashboard script (data gathering, display, navigation) |

## Files to Modify

| File | Change |
|------|--------|
| `claude-code.tmux` | Add `@claude-key-dashboard` and `@claude-dashboard-all-sessions` defaults, register keybinding |
| `README.md` | Document dashboard keybinding and configuration |

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `@claude-key-dashboard` | `M-j` | Keybinding to open dashboard (Alt+J) |
| `@claude-dashboard-all-sessions` | `off` | Scan all tmux sessions, not just current |

## Architecture Notes

### Why `display-popup` and not `status-right`?

The popup is transient -- it appears on demand and disappears with Escape. It doesn't consume permanent status bar real estate. For users with 3 windows, the status bar tabs are sufficient. For users with 10+, the popup provides the overview they need without cluttering the always-visible status bar.

### Why fzf?

fzf provides:
- Fuzzy filtering (type "api" to find the api-server window)
- ANSI color rendering
- Clean bordered UI
- Keyboard navigation

But it's optional. The fallback numbered-list mode works without any dependencies.

### Data flow

```
tmux list-windows -F '...'
        ↓
  Parse window data
        ↓
  Calculate elapsed times
        ↓
  Sort by urgency (question/waiting first)
        ↓
  Format with ANSI colors
        ↓
  Pipe to fzf (or display as numbered list)
        ↓
  User selects a row
        ↓
  tmux select-window -t :N
```

### Performance

- `tmux list-windows` completes in <10ms even with 50 windows
- Elapsed time calculation is pure arithmetic (no external commands)
- The script is invoked on-demand (not polling), so zero background cost
- fzf starts in <50ms on modern systems

## Interaction with Other Features

### Session End / Stale Detector

The dashboard naturally shows `ended` and `stale` states if that feature is implemented. Sessions in those states appear at the bottom of the sorted list (lowest priority) and are greyed out.

### Future: Aggregate Status Widget

The dashboard and a `status-right` summary widget are complementary:
- **Status-right widget** = passive, always visible, "do any sessions need me?"
- **Dashboard popup** = active, on-demand, "which session needs me and why?"

The same data-gathering logic (`tmux list-windows -F '#{@claude-state}'`) can be shared.

## Testing Checklist

- [ ] `prefix + Alt+J` opens popup with session list
- [ ] Sessions sorted by urgency (question/waiting at top)
- [ ] Elapsed time displays correctly for all durations (<1m, <1h, >1h)
- [ ] Selecting a session jumps to correct window
- [ ] Pressing Escape/q closes popup without action
- [ ] Works with fzf installed (fuzzy filtering, colors)
- [ ] Works without fzf (numbered list fallback)
- [ ] Empty state handled ("No Claude Code sessions found")
- [ ] Long window names and paths truncated properly
- [ ] `@claude-key-dashboard ""` disables the keybinding
- [ ] Works on tmux 3.2+ (display-popup)
- [ ] Fallback works on tmux < 3.2 (new-window)
