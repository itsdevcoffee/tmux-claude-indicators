# Mouse Click Bug Investigation - tmux-claude-indicators

## Problem Statement

Window tabs become unclickable in certain Claude Code states:
- ✅ **WORKS**: Active (🫥), Complete (✅)
- ❌ **BROKEN**: Thinking (😜🤪😵‍💫), Question (🔮), Waiting (🫦)

## Deep Dive Analysis

### Research Findings

#### Known tmux Issues with Emojis & Mouse Clicks

1. **Emoji Character Width Issues** ([#4287](https://github.com/tmux/tmux/issues/4287))
   - Certain emojis cause characters to render at wrong positions
   - Affects mouse selection accuracy
   - Bug introduced between tmux 3.3a → 3.4
   - Root cause: tmux's wide character width calculation

2. **Unicode Character Position Problems** ([#632](https://github.com/tmux/tmux/issues/632), [#836](https://github.com/tmux/tmux/issues/836))
   - Unicode in status bars causes rendering glitches
   - Mouse clicks register at wrong locations
   - Terminal emulator compatibility issues

3. **No Documented Blink + Mouse Click Issues**
   - No GitHub issues found linking `blink` attribute to mouse click failures
   - This appears to be an undocumented bug

### Code Analysis

#### Format Strings (`bin/tmux-claude-indicators-on`)

```bash
# Line 6: Non-current window format
##[bg=##791e94##,fg=##ffffff##,bold##,blink]  # ❌ Question state
##[bg=##035ee8##,fg=##ffffff##,bold##,blink]  # ❌ Waiting state

# Line 9: Current window format
##[bg=terminal##,fg=##791e94##,bold##,blink]  # ❌ Question state
##[bg=terminal##,fg=##035ee8##,bold##,blink]  # ❌ Waiting state
```

#### Hook Settings (`hooks/`)

```bash
# notification.sh:73 (Question state)
window-status-style "bg=#791E94,fg=#FFFFFF,bold,blink"  # ❌ Has blink

# notification.sh:84 (Waiting state)
window-status-style "bg=#035EE8,fg=#FFFFFF,bold,blink"  # ❌ Has blink

# user-prompt.sh:35 (Thinking state)
window-status-style "bg=#F706CF,fg=#FFFFFF,bold"  # ✅ No blink, BUT has animated emoji

# session-start.sh:38 (Active state)
window-status-style "bg=#300B5F,fg=#FFFFFF,bold"  # ✅ No blink

# stop.sh:53 (Complete state)
window-status-style "bg=#02F78E,fg=#000000,bold"  # ✅ No blink
```

## ROOT CAUSE IDENTIFIED

### Issue 1: Malformed Format String with Blink Attribute

**Location**: `bin/tmux-claude-indicators-on:6,9`

**Problem**: Extra `##` before `,blink` creates malformed attribute string

```bash
# Current (BROKEN):
##[bg=##791e94##,fg=##ffffff##,bold##,blink]
                                   ↑↑
                              Extra ## here!

# After tmux expansion:
#[bg=#791e94,fg=#ffffff,bold#,blink]
                            ↑
                    Literal # breaks parsing!
```

**Correct format**:
```bash
##[bg=##791e94##,fg=##ffffff##,bold,blink]
                                   ↑
                            No ## before comma!
```

### Issue 2: Rapidly Updating Emoji (Thinking State)

**Location**: `bin/claude-thinking-animator`

**Problem**: 160ms emoji updates cause tmux to recalculate character widths continuously

- Animator updates `@claude-thinking-frame` every 160ms
- Each update triggers tmux status line re-render
- Mouse click detection uses character position mapping
- During rapid updates, click position calculation becomes unreliable

## Proposed Solutions

### Solution 1: Fix Malformed Blink Attribute (High Priority)

Remove the extra `##` before `,blink` in both format strings:

**File**: `bin/tmux-claude-indicators-on`

```bash
# Line 6 - Fix question & waiting states:
-##[bg=##791e94##,fg=##ffffff##,bold##,blink]
+##[bg=##791e94##,fg=##ffffff##,bold,blink]

-##[bg=##035ee8##,fg=##ffffff##,bold##,blink]
+##[bg=##035ee8##,fg=##ffffff##,bold,blink]

# Line 9 - Fix current window question & waiting states:
-##[bg=terminal##,fg=##791e94##,bold##,blink]
+##[bg=terminal##,fg=##791e94##,bold,blink]

-##[bg=terminal##,fg=##035ee8##,bold##,blink]
+##[bg=terminal##,fg=##035ee8##,bold,blink]
```

**Expected Impact**: Should fix Question (🔮) and Waiting (🫦) states immediately.

### Solution 2: Remove Blink Attribute Entirely (Alternative)

If Solution 1 doesn't work, the blink attribute itself might be incompatible with mouse clicks.

**Rationale**:
- Blinking elements require continuous re-rendering
- May interfere with tmux's mouse click position calculation
- Similar to emoji animation issue

**Implementation**:
Remove `blink` from both format strings AND hook settings:

```bash
# bin/tmux-claude-indicators-on
##[bg=##791e94##,fg=##ffffff##,bold]  # No blink
##[bg=##035ee8##,fg=##ffffff##,bold]  # No blink

# hooks/notification.sh
window-status-style "bg=#791E94,fg=#FFFFFF,bold"  # No blink
window-status-style "bg=#035EE8,fg=#FFFFFF,bold"  # No blink
```

### Solution 3: Fix Thinking State Animation (For Completeness)

**Option A**: Slow down animation (320ms instead of 160ms)
- Reduces render frequency
- May reduce mouse click issues

**Option B**: Use static emoji for thinking state
- Replace animated sequence with single emoji
- Eliminates rapid re-rendering

**Option C**: Move emoji outside clickable area
- Place emoji in a separate non-clickable status section
- Preserve animation without affecting clicks

## Testing Plan

1. **Test Solution 1 first** (fix `##,blink` → `,blink`)
   - Reload tmux config
   - Trigger Question state (permission prompt)
   - Click on window tab - should work

2. **If Solution 1 fails**, test Solution 2 (remove blink entirely)
   - Remove blink from format strings AND hooks
   - Test both Question and Waiting states

3. **Test Thinking state separately**
   - If emoji animation still breaks clicks, apply Solution 3

## Technical Notes

### tmux Format String Escaping Rules

Inside `#{?...}` conditionals:
- `##` → Single literal `#`
- `##[` → Literal `#[` (style marker)
- `##300b5f##` → Literal `#300b5f#` (INCORRECT!)
- Should be: `##300b5f` → Literal `#300b5f` (CORRECT)

**BUG**: Current code has trailing `##` on hex codes AND on `bold` attribute, creating malformed style strings.

### Why This Breaks Mouse Clicks

1. Malformed style string → tmux parser fails
2. Partial parsing leaves status bar in inconsistent state
3. Character position map becomes incorrect
4. Mouse clicks use position map → clicks land in wrong place
5. Appears as "unclickable" but actually clicking wrong target

## Sources

- [Emoji causes wrong screen positions - tmux #4287](https://github.com/tmux/tmux/issues/4287)
- [Unicode character in status bar - tmux #632](https://github.com/tmux/tmux/issues/632)
- [Emoji rendering problems - tmux #836](https://github.com/tmux/tmux/issues/836)
- [Window status styles not working - tmux #1909](https://github.com/tmux/tmux/issues/1909)
- [Unicode character width in kitty - tmux #1728](https://github.com/tmux/tmux/issues/1728)
- [tmux Formats Wiki](https://github.com/tmux/tmux/wiki/Formats)
- [tmux Man Page](https://www.man7.org/linux/man-pages/man1/tmux.1.html)
