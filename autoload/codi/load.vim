" Default interpreters
function! s:pp_js(evaled)
  return substitute(a:evaled, '...', '', 'g')
endfunction
function! s:pp_rb(evaled)
  return substitute(a:evaled, "\n=> ", "\n", 'g')
endfunction
function! s:pp_ml(evaled)
  let result = []
  for line in split(a:evaled, "\n")
    " In ocaml, the # of characters before '-' divided by 2 is
    " the number of newlines.
    let match = match(line, '-')
    if match != -1
      call add(result, '# '.repeat("\n# ", match / 2 - 1)."\n".line[match:])
    else
      call add(result, line)
    endif
  endfor
  return join(result, "\n")
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
          \ 'async': 0,
          \ },
      \ 'haskell': {
          \ 'bin': 'ghci',
          \ 'prompt': '^Prelude> ',
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
