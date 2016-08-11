" Default interpreters
function! s:pp_js(evaled)
  return substitute(a:evaled, '...', '', 'g')
endfunction
function! s:pp_hs(evaled)
  let c = substitute(a:evaled, '\(\[?1[hl]\|E\)', '', 'g')
  let c = substitute(c, '', "\n", 'g')
  let l = split(c, "\n")
  let l = []
  for line in split(c, "\n")
    call add(l, line[1:])
  endfor
  return join(l, "\n")
endfunction
function! s:pp_rb(evaled)
  return substitute(a:evaled, "\n=> ", "\n", 'g')
endfunction
let s:codi_default_interpreters = {
      \ 'python': {
          \ 'bin': 'python',
          \ 'prompt': '^\(>>>\|\.\.\.\) ',
          \ },
      \ 'javascript': {
          \ 'bin': 'node',
          \ 'env': 'NODE_DISABLE_COLORS=1',
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
