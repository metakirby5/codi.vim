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
  au CursorHold,CursorHoldI * call codi#update()
augroup END

function! codi#update()
  " Bail if no codi buf to act on
  if !exists('b:codi_bufnr') | return | endif

  " Setup
  let pos = getcurpos()
  exe 'buf '.b:codi_bufnr
  setlocal modifiable

  " Actions
  silent! r !ls

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
    let interpreter = g:codi#interpreters[filetype]
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
  let restore = ''
  for opt in ['scrollbind', 'cursorbind', 'wrap', 'foldenable']
    exe 'let val = &'.opt
    let restore .= '|silent! call setwinvar(bufwinnr('.bufnr.'),"&'.opt.'",'.val.')'
  endfor
  let restore = strpart(restore, 1)

  " Set target buf options
  setlocal scrollbind nowrap nofoldenable
  silent! setlocal cursorbind

  " Save target buf position
  let top = line('w0') + &scrolloff
  let current = line('.')

  " Spawn codi
  20vnew
  setlocal filetype=codi
  let b:codi_leave = restore

  " Get to target buf position
  exe top
  normal! zt
  exe current

  " Return to target split
  wincmd p
  let b:codi_bufnr = bufnr('$')
  call codi#update()
endfunction
