" Utils
function! s:deep_extend(d, e)
  for [k, V] in items(a:e)
    if type(V) == type({})
      let a:d[k] = s:deep_extend(get(a:d, k, {}), V)
    else
      let a:d[k] = V
    endif
    unlet V
  endfor
  return a:d
endfunction

" Default interpreters
function! s:pp_remove_fat_arrow(line)
  " Strip fat arrows
  return substitute(a:line, '=> ', '', 'g')
endfunction
function! s:pp_ml(line)
  " If the line is a prompt
  if a:line =~ '^# '
    " In ocaml, the number of characters before value divided by 2 is
    " the number of newlines.
    let val = match(a:line, '[^# ]')
    return '# '.repeat("\n# ", val / 2 - 1)."\n".a:line[val:]
  else
    return a:line
  endif
endfunction
function! s:pp_r(line)
  " Just return everything after the braces
  return substitute(a:line, '\s*\[\d\+\]\s*\(.*\)$', '\1', '')
endfunction
let s:pp_purs_state = {}
function! s:pp_purs(line)
  let l = a:line
  let rgx_prompt = s:codi_default_interpreters.purescript.prompt
  if exists('g:codi#interpreters.purescript.prompt')
    " Prompt regex overridden by user
    let rgx_prompt = g:codi#interpreters.purescript.prompt
  endif
  let rgxs_ignore = [
      \ '\s*See.*',
      \ '\s*or to contribute.*',
      \ ]
  let rgx_trimlast = '\s*See.*'
  if l =~ rgx_prompt
    " If line saved, send through before next prompt
    if exists('s:pp_purs_state.lastline')
      let l = s:pp_purs_state.lastline . "\n" . l
      unlet s:pp_purs_state.lastline
    endif
  else
    let tmp = ''
    if exists('s:pp_purs_state.lastline')
      if l =~ rgx_trimlast
        " Trim (un-indent) last saved line if special regex matches
        let s:pp_purs_state.lastline = substitute(s:pp_purs_state.lastline, '^\s*', '', '')
      endif
      let tmp = s:pp_purs_state.lastline
    endif
    if max(map(copy(rgxs_ignore), 'l =~ v:val'))
      " Send empty-string if line matched regexes to ignore
      let l = ''
    endif
    if len(l)
      let s:pp_purs_state.lastline = l
      let l = tmp
    endif
    unlet tmp
  endif
  return l
endfunction

" Default rephrasers
function! s:rp_purs(buf)
  let b = a:buf
  " Alternative to Ctrl-d, ":endpaste" will terminate
  " multi-line continuations in psci
  let b = substitute(b, ':endpaste\>', '', 'g')
  " Remove comments. In PSCi they produce an error
  " (Multi-line comments not supported here)
  let b = substitute(b, '\%(^\|[\n\r\x00]\)\s*--[^\n\r\x00]*', '', 'g')
  " Extra newline to flush any remaining 'lastline' from preprocess
  return b . "\n"
endfunction

let s:codi_default_interpreters = {
      \ 'python': {
          \ 'bin': ['env', 'PYTHONSTARTUP=', 'python'],
          \ 'prompt': '^\(>>>\|\.\.\.\) ',
          \ },
      \ 'javascript': {
          \ 'bin': ['node', '-e', 'require("repl").start({ignoreUndefined: true, useGlobal: true})'],
          \ 'prompt': '^\(>\|\.\.\.\+\) ',
          \ },
      \ 'coffee': {
          \ 'bin': 'coffee',
          \ 'prompt': '^coffee> ',
          \ },
      \ 'haskell': {
          \ 'bin': 'ghci',
          \ 'prompt': '^Prelude[^>|]*[>|] ',
          \ },
      \ 'purescript': {
          \ 'bin': ['pulp', 'psci'],
          \ 'prompt': '^[^>…]*[>…] ',
          \ 'rephrase': function('s:rp_purs'),
          \ 'preprocess': function('s:pp_purs'),
          \ 'quitcmd': ':q',
          \ },
      \ 'ruby': {
          \ 'bin': ['irb', '-f'],
          \ 'prompt': '^irb(\w\+):\d\+:\d\+. ',
          \ 'preprocess': function('s:pp_remove_fat_arrow'),
          \ },
      \ 'ocaml': {
          \ 'bin': 'ocaml',
          \ 'prompt': '^# ',
          \ 'preprocess': function('s:pp_ml'),
          \ },
      \ 'r': {
          \ 'bin': 'R',
          \ 'prompt': '^> ',
          \ 'preprocess': function('s:pp_r'),
          \ },
      \ 'clojure': {
          \ 'bin': ['planck', '--verbose', '--dumb-terminal'],
          \ 'prompt': '^.\{-}=> ',
          \ },
      \ 'php': {
          \ 'bin': ['psysh'],
          \ 'prompt': '^\(>>>\|\.\.\.\) ',
          \ 'preprocess': function('s:pp_remove_fat_arrow'),
          \ },
      \ 'lua': {
          \ 'bin': ['lua'],
          \ 'prompt': '^\(>\|>>\) ',
          \ },
       \ 'cpp': {
          \ 'bin': 'cling',
          \ 'prompt': '^\[cling\]\$ ?\?',
          \ 'quitcmd': '.q',
          \ },
      \ }
function! codi#load#interpreters()
  return s:deep_extend(s:codi_default_interpreters, g:codi#interpreters)
endfunction

" Default aliases
let s:codi_default_aliases = {
      \ 'javascript.jsx': 'javascript',
      \ }
function! codi#load#aliases()
  return s:deep_extend(s:codi_default_aliases, g:codi#aliases)
endfunction
