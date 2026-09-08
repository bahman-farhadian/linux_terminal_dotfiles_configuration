" gruvbox.vim — the same palette as this project's tmux.conf and bash prompt,
" hand-picked to the same hex values rather than vendored from upstream. A
" handful of highlight groups, not the hundreds a full plugin defines, because
" this project's own vim config asks for nothing the rest would ever touch.
"
" Needs a true-colour terminal — the one this whole project already assumes
" for the bash prompt and the tmux status bar. `:set termguicolors` below only
" takes effect where the terminal honours it; elsewhere colours fall back to
" whatever the terminal's own palette maps nearest, same as the prompt does.

if exists('g:colors_name')
  hi clear
endif
if has('termguicolors')
  set termguicolors
endif
let g:colors_name = 'gruvbox'

" Background ramp
let s:bg0   = '#282828'
let s:bg1   = '#3c3836'
let s:bg2   = '#504945'
let s:bg3   = '#665c54'
let s:bg0_h = '#1d2021'

" Foreground
let s:fg0  = '#fbf1c7'
let s:fg1  = '#ebdbb2'
let s:fg2  = '#d5c4a1'
let s:grey = '#928374'

" Accents — bright variants, the same ones the bash prompt uses and for the
" same reason: the normal set sits too dark on bg0 to read reliably.
let s:red    = '#fb4934'
let s:green  = '#b8bb26'
let s:yellow = '#fabd2f'
let s:blue   = '#83a598'
let s:purple = '#d3869b'
let s:aqua   = '#8ec07c'
let s:orange = '#fe8019'

function! s:hi(group, fg, bg, attr) abort
  let l:cmd = 'hi ' . a:group
  if a:fg   !=# '' | let l:cmd .= ' guifg=' . a:fg | endif
  if a:bg   !=# '' | let l:cmd .= ' guibg=' . a:bg | endif
  if a:attr !=# '' | let l:cmd .= ' gui=' . a:attr . ' cterm=' . a:attr | endif
  execute l:cmd
endfunction

" Editing surface
call s:hi('Normal',       s:fg1,  s:bg0, '')
call s:hi('NonText',      s:bg3,  '',    '')
call s:hi('LineNr',       s:bg3,  s:bg0, '')
call s:hi('CursorLineNr', s:yellow, s:bg1, 'bold')
call s:hi('CursorLine',   '',     s:bg1, '')
call s:hi('Visual',       '',     s:bg2, '')
call s:hi('MatchParen',   s:bg0,  s:blue, 'bold')
call s:hi('SignColumn',   '',     s:bg0, '')
call s:hi('ColorColumn',  '',     s:bg1, '')
call s:hi('Directory',    s:blue, '',    'bold')

" Search
call s:hi('Search',    s:bg0, s:yellow, '')
call s:hi('IncSearch', s:bg0, s:orange, '')

" Syntax — the groups a real file actually exercises
call s:hi('Comment',    s:grey,   '', 'italic')
call s:hi('Constant',   s:purple, '', '')
call s:hi('String',     s:green,  '', '')
call s:hi('Character',  s:green,  '', '')
call s:hi('Number',     s:purple, '', '')
call s:hi('Boolean',    s:purple, '', '')
call s:hi('Identifier', s:blue,   '', '')
call s:hi('Function',   s:green,  '', 'bold')
call s:hi('Statement',  s:red,    '', 'bold')
call s:hi('Keyword',    s:red,    '', '')
call s:hi('Operator',   s:fg1,    '', '')
call s:hi('PreProc',    s:aqua,   '', '')
call s:hi('Type',       s:yellow, '', 'bold')
call s:hi('Special',    s:orange, '', '')
call s:hi('Underlined', s:blue,   '', 'underline')
call s:hi('Error',      s:bg0,    s:red, 'bold')
call s:hi('Todo',       s:bg0,    s:yellow, 'bold')

" Chrome — status line, tabs, popup menu, splits. Same lightness-ramp idea as
" the tmux status bar: chrome stays on the bg ramp, no accent colours in it
" except where something is genuinely worth flagging.
call s:hi('StatusLine',   s:fg1,  s:bg2, '')
call s:hi('StatusLineNC', s:grey, s:bg1, '')
call s:hi('VertSplit',    s:bg1,  s:bg0, '')
call s:hi('Pmenu',        s:fg1,  s:bg1, '')
call s:hi('PmenuSel',     s:bg0,  s:yellow, 'bold')
call s:hi('TabLine',      s:grey, s:bg1, '')
call s:hi('TabLineSel',   s:bg0,  s:yellow, 'bold')
call s:hi('TabLineFill',  '',     s:bg1, '')

" Diff
call s:hi('DiffAdd',    s:bg0, s:green,  '')
call s:hi('DiffChange', s:bg0, s:yellow, '')
call s:hi('DiffDelete', s:bg0, s:red,    '')
call s:hi('DiffText',   s:bg0, s:orange, 'bold')

delfunction s:hi
