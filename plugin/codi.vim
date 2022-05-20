" User-defined interpreters (see codi-interpreters)
" Entries are in the form of:
"   <filetype>: {
"     'bin': <interpreter binary name, str or array>,
"     'prompt': <vim regex pattern indicating the prompt>,
"     'preprocess': <optional function to run bin output through
"                    before prompt parsing>,
"     'rephrase': <optional function to run buffer contents through
"                    before handing off to bin>,
"   }
" For example:
"   'javascript': {
"       'bin': 'node',
"       'prompt': '^\(>\|\.\.\.\+\) ',
"       'preprocess': function('s:pp_js'),
"       'rephrase': function('s:rp_js'),
"    }
if !exists('g:codi#interpreters')
  let g:codi#interpreters = {}
endif

if !exists('g:codi#command_prefix')
  let g:codi#command_prefix = ['env' , 'INPUTRC=/dev/null']
endif

" Interpreter aliases
" Entries are in the form of:
"   <aliased filetype>: <filetype>
" For example:
"   'javascript.jsx': 'javascript'
if !exists('g:codi#aliases')
  let g:codi#aliases = {}
endif

" What autocmds trigger updates
if !exists('g:codi#autocmd')
  let g:codi#autocmd = ''
endif

" Width of Codi split
if !exists('g:codi#width')
  let g:codi#width = 40
endif

" Split on right?
if !exists('g:codi#rightsplit')
  let g:codi#rightsplit = 1
endif

" Right-align?
if !exists('g:codi#rightalign')
  let g:codi#rightalign = 1
endif

" Close codi on target buffer close?
if !exists('g:codi#autoclose')
  let g:codi#autoclose = 1
endif

" Disable prompt parsing?
if !exists('g:codi#raw')
  let g:codi#raw = 0
endif

" Force sync?
if !exists('g:codi#sync')
  let g:codi#sync = 0
endif

" Start REPL from the directory of the buffer being edited?
if !exists('g:codi#use_buffer_dir')
  let g:codi#use_buffer_dir = 1
endif

" Path for the file where Codi log information. Logging is disabled by default 
if !exists('g:codi#log')
  let g:codi#log = ''
endif

" Toggle virtual text
if !exists('g:codi#virtual_text')
  if has('nvim')
    let g:codi#virtual_text = 1
  else
    let g:codi#virtual_text = 0
  endif
endif

" Character prepended on every virtual text
if !exists('g:codi#virtual_text_prefix')
  let g:codi#virtual_text_prefix = "❯ "
endif

" Highlight group for virtual text output
highlight default link CodiVirtualText Statement

command! -nargs=? -bang -bar -complete=customlist,codi#complete Codi call codi#run(<bang>0, <f-args>)
command! -bar CodiUpdate call codi#update()
command! -nargs=? -complete=customlist,codi#complete CodiNew call codi#new(<f-args>)
if has("nvim")
  command! CodiSelect call codi#select()
  command! CodiExpand call codi#expand()
endif
