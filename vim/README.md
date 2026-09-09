# vim, as configured here

Teaches vim itself, grounded in this config — not a full manual, tables
over paragraphs. Already fluent in vim? [Keys](#keys) at the bottom is
probably all you need.

Optional, separate from every host's own `install.sh`. See the root
[README.md](../README.md#optional-vim) for the file list and how this fits
the project as a whole.

```bash
vim/install.sh      # installs vim if missing, writes ~/.vimrc and the
                     # colour scheme, backs up anything already there
vim/check.sh        # verifies the install actually took
vim/uninstall.sh    # reverses it
```

## Modes

Vim is *modal* — the same key does different things depending which mode
you're in. Knowing which one you're in is the one thing everything else
rests on.

| Mode | For | Enter with |
|---|---|---|
| **Normal** | Moving around, commands. Vim's start state, and where you land after `Esc`. | `Esc`, from anywhere |
| **Insert** | Typing text. | `i` — [below](#entering-text) |
| **Visual** | Selecting text, to act on it. | `v` / `V` / `Ctrl-v` — [below](#visual-mode-selecting-text) |
| **Command-line** | One-off `:` commands — save, quit, search-replace. | `:` |

The one habit worth building: `Esc` before typing a command. Vim commands
typed while still in Insert mode just get typed into the file as text.

## Basic movement

| Keys | Moves |
|---|---|
| `h` `j` `k` `l` | Left / down / up / right (arrow keys work too) |
| `w` / `b` | Forward / back one word |
| `0` / `$` | Start / end of the line |
| `gg` / `G` | Start / end of the file |
| `{N}G` or `:{N}` | Line `N` |

## Entering text

`i` — insert before the cursor. That's the one to know. (`a`/`o`/`O` insert
after the cursor / on a new line below / above, if you ever want them —
`Esc` returns to Normal mode from any of them.)

## Undo and redo

| Keys | Does |
|---|---|
| `u` | Undo the last change |
| `Ctrl-r` | Redo |

## Opening, saving, and closing files

```bash
vim somefile.txt
```

| Command | Does |
|---|---|
| `:e otherfile.txt` | Open another file |
| `:w` | Save |
| `:w newname.txt` | Save as |

**Closing is the one place vim's defaults trip people up.** `:q`/`:x` close
the current *window* — with only one open, the ordinary case, that closes
vim too. Correct vim behaviour, not a bug, but rarely what "I'm done with
this file" means.

| Command | Closes | Vim itself |
|---|---|---|
| `Ctrl-v q` | The buffer | Stays open — switches to another file, or an empty buffer |
| `:x` | Save if changed, then the window | Exits, if that was the last window |
| `:q` | The window (refuses if unsaved) | Exits, if that was the last window |
| `:q!` | The window, discarding changes | Exits, if that was the last window |

`Ctrl-v q` is this config's own addition (`:Bd`), and the one to reach for.

## Editing a file you don't own

The classic "forgot sudo" fix — opened `/etc/something` as your own user,
made the edit, `:w` fails with `E212: Can't open file for writing`:

```vim
:w !sudo tee % > /dev/null
```

`%` is the current filename; `:w !cmd` pipes the buffer to that command's
stdin instead of a file. `sudo tee <filename>` writes it with root
privileges; `> /dev/null` throws away `tee`'s normal stdout echo so it
doesn't clutter the screen. Reload afterwards with `:e!` — the file on
disk changed, but the buffer doesn't know that yet.

## Search

| Keys | Does |
|---|---|
| `/pattern` `Enter` | Search forward |
| `?pattern` `Enter` | Search backward |
| `n` / `N` | Repeat, forward / backward |
| `Ctrl-l` | Clear search highlighting |

Case-insensitive unless the pattern has a capital letter (`foo` matches
`Foo`; `Foo` does not match `foo`).

## Search and replace

| Command | Does |
|---|---|
| `:%s/old/new/g` | Every match, whole file |
| `:%s/old/new/gc` | Same, confirming each — `y`/`n`/`a`/`q` |
| `:s/old/new/g` | Just the current line |
| Select in Visual mode, then `:` | Vim fills in `:'<,'>s/old/new/g` — scoped to the selection |

## Visual mode: selecting text

| Keys | Selects |
|---|---|
| `v` | Character by character |
| `V` | Whole lines |
| `Ctrl-v` (or `Ctrl-q`) | A rectangular block — same column, down several lines |

Extend with movement keys, then act: `y` to yank, `d` to delete, `:` for a
scoped substitute, or the block-edit trick below.

**Edit several lines at once:**

1. `Ctrl-v`, then `j`/`k` to select a block down the left edge — or `$`
   first, to reach each line's actual end regardless of length.
2. `I`, type the text, `Esc` — inserted at the start of every selected
   line. `A` appends at the end instead.

(`Ctrl-v` is this config's leader, so that combination only differs from
plain Visual Block if the very next key is `e`, `f`, `q`, `y` or `p` —
this config's five mapped letters. Anything else, `Ctrl-v` behaves exactly
as vim always has. `Ctrl-q` sidesteps the question entirely.)

## Copy and paste

| Keys | Does |
|---|---|
| `y` | Yank, or `yy` for the current line |
| `d` / `x` | Delete a selection / a line / a character |
| `p` / `P` | Paste after / before the cursor |

Vim's own registers — work across every buffer and tab in the session.

**To or from outside vim** — another tmux pane, another application:

| Keys | Does |
|---|---|
| `Ctrl-v y` (Visual mode) | Yank the selection to the system clipboard |
| `Ctrl-v p` | Paste the system clipboard below the cursor |

Present only where `xclip` and a display exist (this vim package has no
`+clipboard`, so `"+y`/`"+p` do nothing regardless) — silently absent on
the headless hosts.

## Comparing two files

```bash
vim -d fileA fileB          # side by side, differences highlighted
```

or from inside vim, `:vsplit otherfile` then `:diffthis` in both windows.
`Ctrl-w` + `h`/`l`/`j`/`k` moves between the windows.

| Command | Does |
|---|---|
| `]c` / `[c` | Jump to the next / previous difference |
| `:diffget` | Pull the other window's version of this hunk into the current one |
| `:diffput` | Push this hunk's version to the other window |
| `:diffoff` | Turn diff mode off |

## Filtering text through a shell command

Sends a range of lines to an external command and replaces them with its
output — for reformatting, sorting, or reshaping data without leaving vim:

| Command | Does |
|---|---|
| `:%!sort` | Sort the whole file |
| `:%!jq .` | Reformat the whole file as pretty-printed JSON |
| Select lines, then `:!column -t` | Same idea, scoped to a selection |
| `!!command` | Filter just the current line |

## Repeating and automating edits

| Keys | Does |
|---|---|
| `.` | Repeat the last change |
| `qa` ... `q` | Record keystrokes into register `a` |
| `@a` | Play back register `a` |
| `@@` | Repeat the last macro played |

`.` is worth reaching for constantly — after any single edit, moving to a
similar spot and pressing `.` repeats it exactly. Macros are the same idea
for a sequence of edits: record one pass on the first line, then `@a` (or
`5@a` for five more) repeats it down the rest of the file.

## Navigating a project

| Keys | Does |
|---|---|
| `Ctrl-v e` | Toggle a file tree (mnemonic: Explorer) |
| `Ctrl-v f` then a pattern, `Enter` | Search the whole project — results in the quickfix list |
| `:copen` / `:cclose` | Show / hide that list |
| `:cnext` / `:cprev` | Next / previous match |
| `gt` / `gT` | Next / previous tab |

The file tree is netrw, which ships with vim. Once it has focus, these are
netrw's own keys — documented here because nothing else does, not added by
this config:

| Keys | Does |
|---|---|
| `Enter` | Open the file, or enter the directory |
| `-` | Go up one directory |
| `o` / `v` / `t` | Open in a horizontal split / vertical split / new tab |
| `gh` | Toggle hidden (dot) files |

Full list: `:help netrw-quickhelp`, once the tree has focus. Project search
falls back to vim's own (slower) grep when `ripgrep` isn't installed.

## Keys

Everything this config adds:

| Keys | Action |
|---|---|
| `Ctrl-v e` | Toggle the file tree |
| `Ctrl-v f` | Search the project |
| `Ctrl-v q` | Close this buffer, not vim |
| `Ctrl-v y` / `Ctrl-v p` | Yank / paste via the system clipboard |
| `Ctrl-q` | Enter Visual Block (unambiguously, even as `e`/`f`/`q`/`y`/`p`) |
| `Ctrl-l` | Clear search highlighting |

Vim's own defaults, worth knowing, unchanged by this config:

| Keys | Does |
|---|---|
| `.` | Repeat the last change |
| `%` | Jump to the matching bracket / paren / brace |
| `qa` ... `q`, `@a`, `@@` | Record / play back / repeat a macro |
| `Ctrl-w` + `h`/`j`/`k`/`l` | Move between split windows |
| `>>` / `<<`, or select then `>`/`<` | Indent / outdent |
| `gt` / `gT` | Next / previous tab |

## Why the leader is Ctrl-v

Every binding here has to survive tmux, since vim runs inside it almost
always — `.bashrc` starts a tmux session per login. `Ctrl-b` (this
project's tmux prefix) and `Shift-Left`/`Shift-Right` (bound at tmux's
root key table) both looked configured in an earlier version of this file
and never fired inside one. `Ctrl-v` is unclaimed by tmux everywhere except
`copy-mode`, a separate scrollback overlay — so it's the leader instead.
What that costs Visual Block, and why it's small, is covered where it's
actually used: [Visual mode](#visual-mode-selecting-text) above.

## The colour scheme

`colors/gruvbox.vim` — the exact hex values the tmux bar and bash prompt
already use, hand-written rather than vendored from upstream Gruvbox.
Needs a true-colour terminal, same as the bash prompt.
