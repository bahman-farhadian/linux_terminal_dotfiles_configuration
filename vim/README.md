# vim, as configured here

This teaches vim itself, grounded in this specific configuration — not a
general vim manual, and not only a keybinding table. If you already know vim
well, the [Keys](#keys) reference near the bottom is probably all you need.
If you don't, start at the top; each section builds on the one before it.

Optional, and separate from every host's own `install.sh` on purpose —
nothing in the rest of this repository depends on it. See the root
[README.md](../README.md#optional-vim) for the one-paragraph version and how
this fits into the project as a whole.

```bash
vim/install.sh      # installs vim if missing, writes ~/.vimrc and the
                     # colour scheme, backs up anything already there
vim/check.sh        # verifies the install actually took
vim/uninstall.sh    # reverses it — see the file's own comments for exactly
                     # what it touches and what it deliberately leaves alone
```

## The mental model: modes

Vim is *modal*: the same keys do different things depending on which mode
you're in, and knowing which mode you're in is the one piece of vim
literacy everything else rests on.

| Mode | What it's for | How to get there |
|---|---|---|
| **Normal** | Moving around, and every command that isn't literally typing text. The mode vim starts in, and the one you return to after almost everything. | `Esc`, from anywhere |
| **Insert** | Typing text, the way every other editor always is. | `i`, `a`, `o`, `O` (below) — from Normal mode |
| **Visual** | Selecting text, to then act on it. Three variants — see [below](#visual-mode-selecting-text) | `v`, `V`, or `Ctrl-v` — from Normal mode |
| **Command-line** | One-off commands, prefixed with `:` — search-and-replace, saving, quitting, everything that isn't a single keystroke. | `:`, from Normal mode |

The single most common new-to-vim mistake is typing commands while still in
Insert mode, where they just get typed into the file as text. `Esc` first,
always, is the habit worth building before any of the rest of this matters.

## Basic movement

All in Normal mode:

| Keys | Moves |
|---|---|
| `h` `j` `k` `l` | Left, down, up, right — one character/line |
| `w` / `b` | Forward / back one word |
| `0` / `$` | Start / end of the current line |
| `gg` / `G` | Start / end of the file |
| `{N}G` or `:{N}` | Line `N` — `42G` or `:42` jump straight to line 42 |
| `Ctrl-l` | Not movement — clears search highlighting, [below](#search) |

Arrow keys work too; `hjkl` just means never lifting your hands off the
home row, which is the entire reason vim uses them.

## Entering text

From Normal mode:

| Keys | Enters Insert mode |
|---|---|
| `i` | Before the cursor |
| `a` | After the cursor |
| `o` | On a new line below |
| `O` | On a new line above |

Type normally once inside Insert mode. `Esc` returns to Normal mode — that
return trip, not the typing itself, is what most vim keystrokes are spent
on.

## Undo and redo

| Keys | Does |
|---|---|
| `u` | Undo the last change |
| `Ctrl-r` | Redo — undo the undo |

Verified directly rather than assumed: changed a line, `u` restored the
original, `Ctrl-r` brought the change back.

## Opening, saving, and closing files

```bash
vim somefile.txt      # open a file directly
```

From inside vim:

| Command | Does |
|---|---|
| `:e otherfile.txt` | Open another file |
| `:w` | Save |
| `:w newname.txt` | Save as |
| `Ctrl-v e` | Toggle a file tree for browsing the project — [below](#navigating-a-project) |

**Closing is the one place vim's own defaults are worth stopping on.** `:q`
and `:x` close the current *window* — and with only one window open, which
is the ordinary case, that closes vim entirely. That's correct vim
behaviour, not a bug, but it's rarely what "I'm done with this file" means
to anyone arriving from an editor with persistent tabs.

| Command | Closes | Vim itself |
|---|---|---|
| `:w` \| `Ctrl-v q` | Save, then the buffer | Stays open — switches to another file if one is open, otherwise an empty buffer |
| `:x` | Save (only if changed), then the window | Exits, if that was the last window |
| `:q` | The window, refusing if there are unsaved changes | Exits, if that was the last window |
| `:q!` | The window, discarding any unsaved changes | Exits, if that was the last window |

`Ctrl-v q` (mnemonic: Quit — the one that usually means it) is this config's
own addition, `:Bd` under the hood. Verified directly, both ways it can go:
with a second file open, closing one switches to the other; closing the
last one still leaves vim running, on an empty buffer, rather than exiting.

## Search

| Keys | Does |
|---|---|
| `/pattern` then `Enter` | Search forward |
| `?pattern` then `Enter` | Search backward |
| `n` / `N` | Repeat the last search, forward / backward |
| `Ctrl-l` | Clear the highlighting from the last search |

Matches highlight as you type (`incsearch`), and searching is
case-insensitive unless the pattern itself has a capital letter
(`smartcase`) — `foo` matches `Foo`, `Foo` does not match `foo`.

## Search and replace

| Command | Does |
|---|---|
| `:%s/old/new/g` | Every match, whole file |
| `:%s/old/new/gc` | Same, asking before each one — `y`/`n`/`a` (all)/`q` |
| `:s/old/new/g` | Just the current line |
| Select lines in Visual mode, then `:` | Vim fills in `:'<,'>s/old/new/g` on its own, scoped to exactly what was selected |

## Visual mode: selecting text

Three variants, each entered from Normal mode, each ended with `Esc`:

| Keys | Selects |
|---|---|
| `v` | Character by character |
| `V` | Whole lines |
| `Ctrl-v` (or `Ctrl-q` — [why below](#why-the-leader-is-ctrl-v-not-the-default-backslash)) | A rectangular block — the same column, down several lines |

Extend the selection with the usual movement keys (`j`, `w`, `$`, `G`, …),
then act on it — `y` to yank, `d` to delete, `:` for search-and-replace on
just the selection, or the block-edit trick below.

### Editing several lines at once — Visual Block

1. `Ctrl-v` (or `Ctrl-q`), then `j`/`k` to select a block down the left edge
   of several lines — or `$` first, to select to the end of each line
   regardless of length.
2. `I`, type the text, `Esc` — inserted at the start of every selected line.
   `A` instead of `I` appends at the end of each line instead.

This is the one place `Ctrl-v` being this config's leader is worth a
sentence: that combination only behaves differently from plain Visual Block
if the very next key is `e`, `f`, `q`, `y` or `p` — the five letters this
config actually maps. Followed by anything else — `j`, `3j`, `$` — it is
exactly vim's own Visual Block, immediately, with nothing to wait for.
`Ctrl-q` exists for not having to remember that at all: it enters Visual
Block with nothing to disambiguate, ever. Verified with a real key
sequence, not assumed — `Ctrl-v jjy` on three lines produced a genuine
blockwise yank, and `Ctrl-v jjI- Esc` on three more put `- ` at the start
of all three.

## Copy and paste

| Keys | Does |
|---|---|
| `y` | Yank (copy) the selection, or `yy` for the current line |
| `d` / `x` | Delete (cut) the selection, or a line / character |
| `p` / `P` | Paste after / before the cursor |

These are vim's own registers, unaffected by anything in this config, and
work across every buffer and tab in the same session — yank in one file,
paste in another, no special step needed.

**To or from outside vim** — another tmux pane, another application:

| Keys | Does |
|---|---|
| `Ctrl-v y` (Visual mode) | Yank the selection to the system clipboard |
| `Ctrl-v p` (Normal mode) | Paste the system clipboard below the cursor |

Only defined where `xclip` and a display exist — this vim package ships
without `+clipboard` (confirmed with `vim --version`; true on every host
here), so vim's own `"+` register does nothing regardless of display.
Piped through `xclip` instead, the same tool this project's own `cpy` bash
function already uses, and silently absent the same way on the headless
hosts: no display, no mapping, nothing to fail. Verified with a real
`xclip` round trip — yanked two of three lines from a selection, only
those two arrived on the clipboard; pasted a marker back, it landed on
exactly the expected line.

## Navigating a project

| Keys | Does |
|---|---|
| `Ctrl-v e` | Toggle a left-hand file tree (mnemonic: Explorer) |
| `Ctrl-v f` then a pattern, `Enter` | Search the whole project; results land in the quickfix list (mnemonic: Find) |
| `:copen` / `:cclose` | Show / hide that list |
| `:cnext` / `:cprev` | Jump to the next / previous match |
| `gt` / `gT` | Next / previous tab — vim's own default, not a mapping this config adds |

The file tree is netrw, which ships with vim — no plugin. Once it has
focus, these are netrw's own keys, documented here because nothing else
does, not because this config added them:

| Keys | Does |
|---|---|
| `Enter` | Open the file under the cursor, or enter the directory |
| `-` | Go up one directory |
| `o` / `v` / `t` | Open in a horizontal split / vertical split / new tab |
| `gh` | Toggle hidden (dot) files |
| `i` | Cycle listing style — thin, long, wide, tree |
| `qf` | Show information about the file under the cursor |

The full list is netrw's own `:help netrw-quickhelp`, once the tree has
focus.

Project-wide search falls back to vim's own (slower) internal grep when
`ripgrep` isn't installed, rather than erroring — either way the results
land in the same quickfix list.

## Why the leader is Ctrl-v, not the default backslash

Every binding in this file has to work inside tmux, since that is where
vim runs here essentially all the time — `.bashrc` starts a tmux session
for every login. Two keys an earlier version of this config used turned
out to be dead on arrival inside one: `Ctrl-b` is this project's tmux
prefix, so tmux consumes it before vim ever sees it, on every host;
`Shift-Left` and `Shift-Right` are bound at tmux's root key table with no
prefix needed, which claims them the same way, unconditionally. Both
mappings looked configured and neither ever fired in the one place this
config is actually used.

`Ctrl-v` is untouched by tmux everywhere except inside `copy-mode` — a
separate scrollback overlay, not normal pane input, so it never competes
with vim.

Using it as leader barely touches vim's own Visual Block. Vim only defers
to a leader mapping when the very next key completes one — `e`, `f`, `q`,
`y` or `p` here — so pressing `Ctrl-v` and then any other key, a motion
like `j` or a count, falls straight through to Visual Block immediately,
because vim can already see that next key waiting and never has to pause
to disambiguate. Verified with `feedkeys()` rather than assumed: `Ctrl-v
jjy` on three lines produced a genuine blockwise yank, `getregtype()`
reporting vim's own blockwise marker, with these mappings active. The
actual cost is narrower — pressing `Ctrl-v` and then literally one of
those five letters as the first motion of a block selection. `Ctrl-q`
exists for that case and for anyone who would rather not think about it
at all: it enters Visual Block with nothing to disambiguate, ever. Chosen
because vim assigns it no Normal-mode meaning of its own (`:help
i_CTRL-Q`'s "same as Ctrl-v" note is Insert and command-line mode only,
and means something unrelated there — inserting the next character
literally) and tmux does not claim it either, stock or in this project's
tmux.conf. Visual mode's own `Ctrl-v` — switching a selection already in
progress to blockwise — is untouched either way, since only Normal-mode
mappings changed.

## Keys

Every binding this config adds, in one table:

| Keys | Action |
|---|---|
| `Ctrl-v e` | Toggle the file tree |
| `Ctrl-v f` then a pattern, `Enter` | Search the project |
| `Ctrl-v q` | Close this buffer, not vim |
| `Ctrl-v y` (Visual mode) | Yank the selection to the system clipboard |
| `Ctrl-v p` | Paste the system clipboard below the cursor |
| `Ctrl-q` | Enter Visual Block — where bare `Ctrl-v` would, if it were not the leader |
| `Ctrl-l` | Clear search highlighting |

Everything else on this page — modes, movement, undo, `gt`/`gT`, the
netrw keys inside the tree — is vim's own, or netrw's own, unchanged.
Nothing here needed a plugin.

## The colour scheme

`colors/gruvbox.vim` is hand-written to the exact hex values the tmux
status bar and bash prompt elsewhere in this project already use, not
vendored from upstream Gruvbox — a file in this repository, not a `git
clone` of someone else's. Needs a true-colour terminal, the same
requirement the bash prompt already has.
