" User-defined interpreters (see codi-interpreters)
" Entries are in the form of
"   <filetype>: {
"     'bin': <interpreter binary>,
"     'prompt': <regex pattern indicating the prompt>,
"     'filter': <optional command to pipe output through>,
"   }
if !exists('g:codi#interpreters')
  let g:codi#interpreters = {}
endif

" Width of Codi split
if !exists('g:codi#width')
  let g:codi#width = 40
endif

command! -nargs=? -bar -complete=filetype Codi call codi#interpret(<f-args>)
