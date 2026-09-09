# vim, as configured here

Teaches vim itself, grounded in this config — not a full manual, tables
over paragraphs. Already fluent in vim? [Keys](#keys) at the bottom is
probably all you need.

Optional, separate from every host's own `install.sh`. Installed once, for
every user on the machine — see the root [README.md](../README.md#optional-vim)
for the file list and how this fits the project as a whole.

```bash
sudo vim/install.sh   # installs vim if missing, writes the config and colour
                      # scheme for every user, backs up anything already there
vim/check.sh          # verifies the install actually took
sudo vim/uninstall.sh # reverses it
```

If an account already has its own `~/.vimrc`, vim uses that instead — a
personal vimrc always wins over this one, not the other way round.
`vim/check.sh` warns if the account running it has one.

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

Typing bare `vim`, with no file, lands directly in Insert mode — no splash
screen, cursor ready, since opening it with nothing to open means "I want
to start typing," not "browse a file." `vim somefile.txt` still opens in
Normal mode as always, since there's a real file to look at first.

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

**Edit several lines at once — the everyday case is commenting out a block
of a config file:**

```
listen 80;                    listen 80;
server_name example.com;  →   # server_name example.com;
root /var/www;                # root /var/www;
```

1. Put the cursor on `server_name`'s line, `Ctrl-v`, then `j` to extend the
   block down to `root`'s line too.
2. `I`, type `# `, `Esc` — inserted at the start of both selected lines at
   once.

`A` instead of `I` appends at the end of each line rather than the start —
same idea, useful for adding a trailing `;` to several lines instead of a
leading `#`.

`Ctrl-v` is also this config's leader (below), which only matters if the
very next key you press is `e`, `f`, `q`, `y` or `p`. Any other key, and
`Ctrl-v` is plain Visual Block, same as always. `Ctrl-q` always is, no
exceptions, if you'd rather not think about it.

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

## Everyday config-file edits

The things that come up constantly editing `/etc` and its relatives —
mostly the same tools as above, applied to the specific shape these edits
usually take.

| Task | Keys |
|---|---|
| Comment out one line | `0i# ` `Esc` |
| Comment out several lines | Block Visual — [above](#visual-mode-selecting-text) |
| Uncomment several lines | `0`, `Ctrl-v`, extend down and across the `# `, then `d` — deletes it from every selected line at once |
| Delete a line entirely | `dd` |
| Duplicate a line (to edit the copy) | `yy` then `p` |
| Repeat the last edit at a similar spot | `.` |

Verified directly, not assumed: block-selecting `# ` on three commented
lines and pressing `d` removed it from all three in one motion — the exact
reverse of the block-comment above. `.` is worth reaching for on its own,
constantly — after any single change, moving to a similar spot and
pressing `.` repeats it exactly, no selection needed.

## Navigating a project

| Keys | Does |
|---|---|
| `Ctrl-v e` | Toggle a file tree (mnemonic: Explorer) |
| `Ctrl-v f` then a pattern, `Enter` | Search the whole project — results in the quickfix list |
| `:copen` / `:cclose` | Show / hide that list |
| `:cnext` / `:cprev` | Next / previous match |
| `gt` / `gT` | Next / previous tab |

Opening a directory instead of a file (`vim .`, or `vim somedir/`) does
*not* show the tree on its own — press `Ctrl-v e` same as always. Earlier
this auto-opened, using vim's own built-in netrw; dropped on purpose, since
it and the leader-e sidebar didn't agree on what "already open" meant and
would occasionally show two trees at once, right where a duplicate is
hardest to notice.

The file tree is NERDTree (`pack/dist/start/nerdtree`, vendored from
[amix/vimrc](https://github.com/amix/vimrc), WTFPL) — the one plugin in
this setup, replacing vim's own netrw. Once it has focus, these are
NERDTree's own keys — documented here because nothing else does, not added
by this config:

| Keys | Does |
|---|---|
| `Enter` / `o` | Open the file, or enter the directory |
| `i` / `s` | Open in a horizontal split / vertical split |
| `t` | Open in a new tab |
| `u` | Go up one directory |
| `I` | Toggle hidden (dot) files |
| `R` | Refresh |
| `q` | Close the tree |

Full list: `:help NERDTreeMappings`, once the tree has focus. Project
search falls back to vim's own (slower) grep when `ripgrep` isn't installed.

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

Vim almost always runs inside tmux here, and tmux claims some keys before
vim ever sees them — `Ctrl-b`, `Shift-Left`, `Shift-Right`. `Ctrl-v` is one
of the few keys tmux never touches, so it's the leader instead of vim's own
default backslash. What that costs Visual Block is covered above, under
[Visual mode](#visual-mode-selecting-text) — small, and `Ctrl-q` avoids it
entirely.

## The colour scheme

`colors/gruvbox.vim` — the same hex values as the tmux bar and bash prompt,
hand-written rather than vendored from upstream Gruvbox. Needs a true-colour
terminal, same as the bash prompt.

The editing area itself has no background colour set, so it just shows
whatever the terminal's own background is — same idea as `tmux.conf`'s own
status bar. Only things meant to stand out — the cursor line, a selection,
the status line, tabs — keep a fixed colour.
