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
