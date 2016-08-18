" Utils
function! s:deep_extend(d, e)
  for [k, v] in items(a:e)
    if type(v) == type({})
      let a:d[k] = s:deep_extend(get(a:d, k, {}), v)
    else
      let a:d[k] = v
    endif
    unlet v
  endfor
  return a:d
endfunction

" Default interpreters
function! s:pp_rb(line)
  " Strip fat arrows
  return substitute(a:line, '=> ', '', 'g')
endfunction
function! s:pp_ml(line)
  " If the line is a prompt
  if match(a:line, '^# ') != -1
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
          \ 'bin': 'python',
          \ 'prompt': '^\(>>>\|\.\.\.\) ',
          \ },
      \ 'javascript': {
          \ 'bin': 'node',
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
          \ 'bin': 'irb',
          \ 'prompt': '^irb(\w\+):\d\+:\d\+. ',
          \ 'preprocess': function('s:pp_rb'),
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
          \ }
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
