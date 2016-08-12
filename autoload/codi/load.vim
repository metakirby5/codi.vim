" Default interpreters
function! s:pp_js(output)
  return substitute(a:output, '...', '', 'g')
endfunction
function! s:pp_rb(output)
  return substitute(a:output, "\n=> ", "\n", 'g')
endfunction
function! s:pp_ml(output)
  let result = []
  for line in split(a:output, "\n")
    " If the line is a prompt
    if match(line, '^# ') != -1
      " In ocaml, the number of characters before value divided by 2 is
      " the number of newlines.
      let val = match(line, '[^# ]')
      call add(result, '# '.repeat("\n# ", val / 2 - 1)."\n".line[val:])
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
          \ 'prompt': '^\(>\|\.\.\.\+\) ',
          \ 'preprocess': function('s:pp_js'),
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
