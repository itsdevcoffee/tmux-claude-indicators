# mouse click bug - RESOLVED

## root cause (discovered 2026-01-22)

**The bug:** Hex colors in `window-status-style` corrupt tmux's range declarations.

When `window-status-style` is set with hex colors (e.g., `bg=#300B5F`), tmux expands it via `#{E:window-status-style}` into the `status-format`. The `#` character is special in tmux format strings, causing corruption:

```
# Before (corrupted):
range=window|2 bg=#300B5F,fg=##FFFFF,bold bold]  ← ##FFFFF is wrong!
range=window|4 bg=##-706CF,fg=##-FFFFF,bold bold]  ← completely mangled!

# After (fixed with colour256):
range=window|2 bg=colour54,fg=colour255,bold bold]  ← clean!
range=window|4 bg=colour200,fg=colour255,bold bold]  ← clean!
```

**The fix:** Use `colour256` indices instead of hex colors in `window-status-style`.

## colour256 mapping

| State    | Hex Color | colour256 | Description   |
|----------|-----------|-----------|---------------|
| active   | #300B5F   | colour54  | deep purple   |
| thinking | #F706CF   | colour200 | hot pink      |
| question | #791E94   | colour128 | deep violet   |
| waiting  | #035EE8   | colour33  | laser blue    |
| complete | #02F78E   | colour48  | matrix green  |

---

# historical context (pre-fix)

## problem statement

**working:** colors, emojis, animations all display correctly ✅
**broken:** mouse clicks on certain window tabs don't switch windows ❌

## current status

### what works ✅
- all 5 claude states display with correct cyberpunk colors
- emojis show correctly (🤖 😜 🔮 🫦 ✅)
- animations work (thinking state rotates emojis every 160ms)
- hooks execute properly and set window-status-style
- current window has ▶ arrow indicator
- color scheme is vibrant and clear

### what's broken ❌
**mouse clicks don't work on:**
- 🤖 active (robot) state tabs
- 😜 thinking state tabs
- 🔮 question state tabs
- 🫦 waiting state tabs

**mouse clicks DO work on:**
- ✅ complete state tabs
- non-claude tabs (rust brown background)

## technical details

### current implementation

**file:** `bin/tmux-claude-code-on`

uses **embedded colors in format strings** because `window-status-style` (set by hooks) doesn't work - gets overridden or ignored.

**format string structure:**
```tmux
window-status-format '#{?@claude-state,
  #{?#{==:#{@claude-state},active},#[bg=##300B5F#,fg=##FFFFFF#,bold],
  #{?#{==:#{@claude-state},thinking},#[bg=##F706CF#,fg=##FFFFFF#,bold],
  #{?#{==:#{@claude-state},question},#[bg=##791E94#,fg=##FFFFFF#,bold#,blink],
  #{?#{==:#{@claude-state},waiting},#[bg=##035EE8#,fg=##FFFFFF#,bold#,blink],
  #{?#{==:#{@claude-state},complete},#[bg=##02F78E#,fg=##000000#,bold],
  #[bg=default#,fg=default]
  }
},
#[bg=##8B4513#,fg=##FFE4B5#,bold]  ← fallback for no claude state
} │ #I #W #{emoji-based-on-state}'
```

### the mystery

**why do some states click and others don't?**

**clickable states:**
- complete: `#[bg=##02F78E#,fg=##000000#,bold]`
- no claude: `#[bg=##8B4513#,fg=##FFE4B5#,bold]`

**non-clickable states:**
- active: `#[bg=##300B5F#,fg=##FFFFFF#,bold]`
- thinking: `#[bg=##F706CF#,fg=##FFFFFF#,bold]`
- question: `#[bg=##791E94#,fg=##FFFFFF#,bold#,blink]`
- waiting: `#[bg=##035EE8#,fg=##FFFFFF#,bold#,blink]`

**notable patterns:**
- all use similar syntax: `#[bg=##HEX#,fg=##HEX#,bold...]`
- extra `#` after each hex code
- question/waiting have extra `#` before `,blink`
- complete and no-claude use identical syntax but ARE clickable
- no obvious pattern distinguishing clickable from non-clickable

## what we've tried

### attempt 1: remove extra # characters
**commit:** 50ecc92

changed: `#[bg=##300B5F#,fg=##FFFFFF#,bold]` → `#[bg=##300B5F,fg=##FFFFFF,bold]`

**result:** hex codes rendered as literal text in status bar, completely broken ❌

### attempt 2: simple format strings (no embedded colors)
let hooks set colors via `window-status-style`, format strings just show emojis.

**result:**
- colors didn't show (window-status-style ignored/overridden)
- clicks still broken ❌

### attempt 3: disable tmux2k
disabled tmux2k plugin entirely to prevent format override.

**result:** colors still didn't show via window-status-style ❌

### attempt 4: add #[default] to force inheritance
added `#[default]` at start of format string to force window-status-style colors.

**result:** no colors showed ❌

### current state: working colors, broken clicks
**commit:** 188b818 (restored)

colors work perfectly, but mouse clicks broken on active/thinking/question/waiting states.

## environment details

- **repo:** `/home/maskkiller/dev-coffee/repos/tmux-claude-code/`
- **terminal:** kitty with true color support
- **plugins:** tmux2k (currently disabled), gpakosz/.tmux
- **tmux version:** run `tmux -V` to check
- **development mode:** using local repo via `run-shell`, not TPM

## files to investigate

**primary:**
- `bin/tmux-claude-code-on` - format string definitions (lines 7-11)

**supporting:**
- `hooks/*.sh` - set @claude-state and window-status-style
- `claude-code.tmux` - color/emoji defaults
- `.tmux.conf.local` - tmux configuration and keybindings

## observations

### extra # character mystery

**tmux format string syntax:**
- literal `#` must be escaped as `##`
- format codes use `#[...]` syntax
- hex colors need `##`: `bg=##300B5F`

**current format has:**
- `#[bg=##300B5F#,fg=##FFFFFF#,bold]`
  - `##300B5F#` - extra `#` after hex
  - `##FFFFFF#` - extra `#` after hex

**theory:** these extra `#` might be:
1. breaking tmux parser → non-clickable regions
2. needed for colors to render → removing them shows literal text
3. some weird escaping requirement we don't understand

### clickable vs non-clickable pattern

**both clickable and non-clickable states:**
- use nested conditionals (6 levels deep)
- have emojis after window name
- use similar format code syntax

**only complete/no-claude are clickable:**
- complete is last in conditional chain
- no-claude is the fallback (outside conditionals)
- maybe position in conditional tree matters?

### emoji-specific issues

**thinking state uses:**
```tmux
#{@claude-thinking-frame}
```
instead of a static emoji. this variable is updated every 160ms by background animator.

**could this cause issues?**
- variable contains multi-byte emoji characters
- changes frequently while user tries to click
- might confuse tmux's mouse region detection

## questions for investigation

1. **is there a tmux format string complexity limit?**
   - 6 levels of nested conditionals
   - ~500+ characters
   - might exceed parser capabilities

2. **do the extra # characters have meaning?**
   - why do colors only work WITH them?
   - why does removing them show literal text?
   - is this a tmux version-specific behavior?

3. **is mouse region detection emoji-sensitive?**
   - do certain emojis break clickable regions?
   - is the thinking variable-emoji the culprit?
   - test with ascii characters instead?

4. **can we use a different tmux feature?**
   - window-status-style doesn't work (overridden)
   - format strings work for colors but break clicking
   - alternatives: pane titles? border colors? status-right?

5. **is the conditional nesting order relevant?**
   - complete is last → clickable
   - active/thinking are early → non-clickable
   - try reordering to see if it matters?

## debugging commands

```bash
# check current window state
tmux show-window-option @claude-state

# check applied style
tmux show-window-option window-status-style

# check format strings
tmux show -g window-status-format
tmux show -g window-status-current-format

# check tmux version
tmux -V

# test with minimal format (no conditionals)
tmux set -g window-status-format ' │ #I #W '
tmux set -g window-status-current-format ' ▶ #I #W '
# ^ if this is clickable, problem is in conditionals

# test with simple color code
tmux set -g window-status-format '#[bg=##300B5F#,fg=##FFFFFF#,bold] │ #I #W '
# ^ if not clickable, problem is the extra #
```

## color scheme reference

```bash
# cyberpunk/tron theme
active: bg=#300B5F (deep purple), fg=#FFFFFF (white)
thinking: bg=#F706CF (hot pink), fg=#FFFFFF (white)
question: bg=#791E94 (deep violet), fg=#FFFFFF (white), blink
waiting: bg=#035EE8 (laser blue), fg=#FFFFFF (white), blink
complete: bg=#02F78E (matrix green), fg=#000000 (black)
no claude: bg=#8B4513 (rust brown), fg=#FFE4B5 (wheat)
```

## repository context

### local development setup
- editing files in `/home/maskkiller/dev-coffee/repos/tmux-claude-code/`
- using `run-shell` to load local version (not TPM)
- keybindings point to local dev paths
- changes applied via `tmux source-file ~/.tmux.conf` or `prefix + K`

### hook system
claude code hooks trigger bash scripts that:
1. set @claude-state variable (active/thinking/question/waiting/complete)
2. set window-status-style with background colors
3. spawn/kill background processes (animator, timers)

hooks are registered in `~/.claude/settings.json` pointing to local dev paths.

## suggested investigation approach

1. **test with minimal format**
   - start with basic clickable format
   - add ONE conditional at a time
   - find which addition breaks clicking

2. **test emoji theory**
   - replace all emojis with ascii (A/T/Q/W/C)
   - if clicking works, problem is emoji-related
   - try different emojis to find which break it

3. **test color code syntax**
   - try different # escaping patterns
   - maybe `#[bg=#300B5F]` works? (single # for literal)
   - test different tmux versions if available

4. **research tmux format limitations**
   - check tmux docs/issues for known bugs
   - search for mouse click + format string problems
   - check if tmux version matters

5. **consider alternative approaches**
   - use status-right with custom segments
   - use pane border colors (changes border based on state)
   - accept limitation and document keyboard-only navigation

## success criteria

**ideal:** colors work AND all states clickable ✅ ACHIEVED!
**acceptable:** colors work, document mouse limitation
**unacceptable:** no colors (current state without commit 188b818)

## resolution

**Fixed on 2026-01-22** by replacing hex colors with colour256 indices in all hooks:
- `hooks/session-start.sh`
- `hooks/user-prompt.sh`
- `hooks/notification.sh`
- `hooks/stop.sh`

The fix avoids tmux's format string parsing issue where `#` characters in hex colors get corrupted when expanded via `#{E:window-status-style}` into range declarations.

Sources that helped diagnose:
- [tmux GitHub issue #1332](https://github.com/tmux/tmux/issues/1332) - comma escaping in conditionals
- [tmux GitHub issue #4011](https://github.com/tmux/tmux/issues/4011) - range declarations and `#[norange]`
- [tmux format-strings.sh test suite](https://github.com/tmux/tmux/blob/master/regress/format-strings.sh)
