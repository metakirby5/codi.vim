" User-defined interpreters (see codi-interpreters)
" Entries are in the form of:
"   <filetype>: {
"     'bin': <interpreter binary>,
"     'env': <optional environment variables for bin>,
"     'prompt': <awk pattern indicating the prompt>,
"     'preprocess': <optional command to pipe output through
"                    before prompt parsing>,
"   }
" For example:
"   'javascript': {
"     'bin': 'node',
"     'env': 'NODE_DISABLE_COLORS=1',
"     'prompt': '^(>|\.\.\.) ',
"     'preprocess': 'sed "s/\[\(1G\|0J\|3G\)//g"',
"   }
if !exists('g:codi#interpreters')
  let g:codi#interpreters = {}
endif

" Interpreter aliases
" Entries are in the form of:
"   <aliased filetype>: <filetype>
" For example:
"   'javascript.jsx': 'javascript'
if !exists('g:codi#aliases')
  let g:codi#aliases = {}
endif

" Width of Codi split
if !exists('g:codi#width')
  let g:codi#width = 40
endif

" Close codi on target buffer close?
if !exists('g:codi#autoclose')
  let g:codi#autoclose = 1
endif

" Disable prompt parsing?
if !exists('g:codi#raw')
  let g:codi#raw = 0
endif

command! -nargs=? -bang -bar -complete=filetype Codi call codi#run('<bang>', <f-args>)
