let g:codi#layout = 'botright vertical 20'
let g:codi#interpreters = {
      \ 'python': {
          \ 'bin': 'python',
          \ 'pre': 'from __future__ import print_function; import sys',
          \ 'print_pre': 'print(',
          \ 'print_post': 'file=sys.stderr)'
          \ }
      \ }

command! -nargs=? -bar Codi call codi#interpret(<f-args>)
