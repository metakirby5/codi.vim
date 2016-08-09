" Default interpreters
let s:codi_interpreters = {
      \ 'python': {
          \ 'bin': 'python',
          \ 'prompt': '^(>>>|\.\.\.) ',
          \ },
      \ 'javascript': {
          \ 'bin': 'node',
          \ 'env': 'NODE_DISABLE_COLORS=1',
          \ 'prompt': '^(>|\.\.\.+) ',
          \ 'preprocess': 'sed "s/\[\(1G\|0J\|3G\)//g"',
          \ },
      \ 'haskell': {
          \ 'bin': 'ghci',
          \ 'prompt': '^Prelude> ',
          \ 'preprocess':
            \ 'sed "s/\(\[?1[hl]\|E\)//g" | tr "" "\n" | cut -c2-',
          \ },
      \ 'ruby': {
          \ 'bin': 'irb',
          \ 'prompt': '^irb\([_a-zA-Z0-9]+\):[0-9]+:[0-9]+. ',
          \ 'preprocess':
            \ 'sed "s/^=> //g"',
          \ },
      \ }
function! codi#defaults#interpreters()
  return extend(s:codi_interpreters, g:codi#interpreters)
endfunction

" Default aliases
let s:codi_aliases = {
      \ 'javascript.jsx': 'javascript',
      \ }
function! codi#defaults#aliases()
  return extend(s:codi_aliases, g:codi#aliases)
endfunction
