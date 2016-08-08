" Default interpreters
let s:codi_interpreters = {
      \ 'python': {
          \ 'bin': 'python',
          \ 'pre': "
                \exec(",
          \ 'post': "
                \)\n",
          \ 'eval_pre': "
                \try: print(eval(",
          \ 'eval_post': "
                \))\nexcept: print ''",
          \ },
      \ }
" Load user-defined interpreters
call extend(s:codi_interpreters, g:codi#interpreters)

" Actions on codi
augroup CODI
  au!
  au FileType codi setlocal
        \ buftype=nofile nomodifiable nomodified
        \ nomodeline nonumber nowrap
        \ foldcolumn=0 nofoldenable winfixwidth
        \ scrollbind | silent! setlocal cursorbind | syncbind
  au BufWinLeave * if exists('b:codi_leave') | exe b:codi_leave | endif
augroup END

" Update codi buf on buf change
augroup CODI_TARGET
  au!
  au CursorHold,CursorHoldI * silent! call s:codi_update()
augroup END

function! s:codi_update()
  " Bail if no codi buf to act on
  if !exists('b:codi_bufnr') | return | endif

  " Setup
  let pos = getcurpos()
  let lim = line('$')

  " Escape quotes
  let unescaped_lines = getline('^', '$')
  let lines = []
  for line in unescaped_lines
    call add(lines, substitute(line, '"', '\\"', 'g'))
  endfor

  exe 'buf '.b:codi_bufnr
  setlocal modifiable

  " Clear buffer
  let codi_pos = getcurpos()
  normal! ggdG

  " For every line, interpret up to that point
  let cur = 0
  while cur < lim
    " Build the content to run
    let content =
          \ b:codi_interpreter['pre']                                     .'"'
          \.join(lines[0:cur], '\n')                                      .'"'
          \.b:codi_interpreter['post']
          \.b:codi_interpreter['eval_pre']                                .'"'
          \.lines[cur]                                                    .'"'
          \.b:codi_interpreter['eval_post']

    " Read in the last line printed
    exe 'silent! r !'
          \.b:codi_interpreter['bin'].' 2>&1 <<< '.shellescape(content)
          \.' | tail -n1'

    let cur += 1
  endwhile

  " Kill the empty line at the start and return to position
  normal! ggdd
  call setpos('.', codi_pos)

  " Teardown
  setlocal nomodifiable
  buf #
  call setpos('.', pos)
endfunction

function! codi#interpret(...)
  " Get filetype from arg if exists
  if exists('a:1')
    let filetype = a:1
    exe 'setlocal filetype='.filetype
  else
    let filetype = &filetype
  endif

  try
    let interpreter = s:codi_interpreters[filetype]
  " If key not found
  catch E716
    let filetype = !empty(filetype) ? filetype : 'plaintext'
    echohl WarningMsg | echom filetype.' not supported.' | echohl None
    return
  endtry

  " If we already have a codi instance for the buffer, kill it
  if exists('b:codi_bufnr')
    exe 'bdel '.b:codi_bufnr
    unlet b:codi_bufnr
  endif

  " Adapted from:
  " https://github.com/tpope/vim-fugitive/blob/master/plugin/fugitive.vim#L1988

  " Restore target buf options on codi close
  let bufnr = bufnr('%')
  let restore = 'bdel|buf'.bufnr.'|unlet b:codi_bufnr'
  for opt in ['scrollbind', 'cursorbind', 'wrap', 'foldenable']
    exe 'let val = &'.opt
    let restore .= '|let &'.opt.'='.val.''
  endfor

  " Set target buf options
  setlocal scrollbind nowrap nofoldenable
  silent! setlocal cursorbind

  " Save target buf position
  let top = line('w0') + &scrolloff
  let current = line('.')

  " Spawn codi
  20vnew
  setlocal filetype=codi
  let b:codi_target = bufnr
  let b:codi_leave = restore
  let b:codi_interpreter = interpreter

  " Get to target buf position
  exe top
  normal! zt
  exe current

  " Return to target split
  wincmd p
  let b:codi_bufnr = bufnr('$')
  silent! call s:codi_update()
endfunction
