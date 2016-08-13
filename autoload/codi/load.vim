" Default interpreters
function! s:pp_js(line)
  " Strip escape codes
  return substitute(a:line, '\[\d\(\a\|\dm\)', '', 'g')
endfunction
function! s:pp_hs(line)
  " BSD is fine.
  let s:uname = system('uname -s')
  if s:uname =~ 'Darwin' || s:uname =~ 'BSD'
    return a:line
  endif

  " On Linux, strip escape codes and add newlines where they should go
  let c = substitute(a:line, '\(\[?1[hl]\|E\)', '', 'g')
  return substitute(c, '', "\n", 'g')
endfunction
function! s:pp_rb(line)
  " Strip fat arrows
  return substitute(a:line, "=> ", '', 'g')
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
let s:codi_default_interpreters = {
      \ 'python': {
          \ 'bin': 'python',
          \ 'prompt': '^\(>>>\|\.\.\.\) ',
          \ },
      \ 'javascript': {
          \ 'bin': 'node',
          \ 'prompt': '^\(>\|\.\.\.\+\) ',
          \ 'preprocess': function('s:pp_js'),
          \ },
      \ 'haskell': {
          \ 'bin': 'ghci',
          \ 'prompt': '^Prelude> ',
          \ 'preprocess': function('s:pp_hs'),
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
      \ }
function! codi#load#interpreters()
  return extend(s:codi_default_interpreters, g:codi#interpreters)
endfunction

" Default aliases
let s:codi_default_aliases = {
      \ 'javascript.jsx': 'javascript',
      \ }
function! codi#load#aliases()
  return extend(s:codi_default_aliases, g:codi#aliases)
endfunction
