" User-defined interpreters (see codi-interpreters)
" Entries are in the form of
"   <filetype>: {
"     'bin': <interpreter binary>,
"     'env': <optional environment variables for bin>,
"     'prompt': <regex pattern indicating the prompt>,
"     'prepipe': <optional command to pipe through first>,
"     'postpipe': <optional command to pipe through last>,
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

command! -nargs=? -bar -complete=filetype Codi call codi#start(<f-args>)
