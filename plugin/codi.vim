let g:codi#interpreters = {
      \ 'python': {
          \ 'bin': 'python',
          \ 'pre': '
                \ from __future__ import print_function;
                \ import sys;
                \ print(eval("""',
          \ 'post': '
                \ """), file=sys.stderr)',
          \ },
      \ }

command! -nargs=? -bar -complete=filetype Codi call codi#interpret(<f-args>)
