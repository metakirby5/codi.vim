" User-defined interpreters (see codi-interpreters)
" Entries are in the form of
"   <filetype>: {
"     'bin': <interpreter binary>,
"     'env': <optional environment variables for bin>,
"     'prompt': <awk pattern indicating the prompt>,
"     'preprocess': <optional command to pipe output through
"                    before prompt parsing>,
"   }
if !exists('g:codi#interpreters')
  let g:codi#interpreters = {}
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
