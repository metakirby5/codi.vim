" User-defined interpreters
" Entries are in the form of
"   <filetype>: {
"     'bin': <interpreter binary>,
"     'pre': <string to inject at start>,
"     'post': <string to inject at end>
"   }
let g:codi#interpreters = {}

command! -nargs=? -bar -complete=filetype Codi call codi#interpret(<f-args>)
