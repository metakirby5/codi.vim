" Default interpreters
let s:codi_interpreters = {
      \ 'python': {
          \ 'bin': 'python',
          \ 'prompt': '>>> |\.\.\. ',
          \ 'prepipe': 'tail -n+4',
          \ },
      \ 'javascript': {
          \ 'bin': 'node',
          \ 'prompt': '> ',
          \ 'postpipe': 'sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g"',
          \ },
      \ 'haskell': {
          \ 'bin': 'ghci',
          \ 'prompt': 'Prelude> ',
          \ 'prepipe': 'tr "" "\n" | sed "/\[?1./d"',
          \ 'postpipe': 'cut -c2-',
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

" Display a warning message
function! s:warn(msg)
  echohl WarningMsg | echom a:msg | echohl None
endfunction

" Update the codi buf
function! s:codi_update()
  " Bail if no codi buf to act on
  if !exists('b:codi_bufnr') | return | endif

  " Setup target buf
  let pos = getcurpos()
  let num_lines = line('$')
  let content = shellescape(join(getline('^', '$'), "\n"))

  " Setup codi buf
  exe 'buf '.b:codi_bufnr
  setlocal modifiable
  let codi_pos = getcurpos()
  normal! gg_dG

  " Execute our code by:
  "   - Using script to simulate a tty on...
  "   - The interpreter, which will take...
  "   - Our shell-escaped buffer as input, then piped through...
  "   - tail, to get rid of the lines we input...
  "   - any user-provided prepipe...
  "   - sed, to remove color codes...
  "   - awk, to only print the line right before a prompt...
  "   - tail again, to remove the first blank line...
  "   - tr, to remove those nasty line feeds...
  "   - any user-provided postpipe
  " TODO linux script support
  exe 'r !script -q /dev/null '
        \.b:codi_interpreter['bin']
        \.' <<< '.content
        \.' | tail -n+'.(num_lines + 1)
        \.' | '.get(b:codi_interpreter, 'prepipe', 'cat')
        \.' | awk "{'
          \.'if (/'.b:codi_interpreter['prompt'].'/)'
            \.'{ print taken; taken = \"\" }'
          \.'else'
            \.'{ if (\$0) { taken = \$0 } }'
        \.'}" | tail -n+2'
        \.' | tr -d $"\r"'
        \.' | '.get(b:codi_interpreter, 'postpipe', 'cat')

  " Teardown codi buf
  normal! gg_dd
  call setpos('.', codi_pos)
  setlocal nomodifiable

  " Teardown target buf
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
  " If interpreter not found...
  catch E716
    if empty(filetype)
      call s:warn('Cannot run Codi with empty filetype.')
    else
      call s:warn('No interpreter for '.filetype.'.')
    endif
    return
  endtry

  " Check if required keys present
  let error = 0
  for key in ['bin', 'prompt']
    if !has_key(interpreter, key)
      call s:warn('Interpreter for '.filetype.' missing required key '.key)
      let error = 1
    endif
  endfor
  if error | return | endif

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
    if exists('&'.opt)
      exe 'let val = &'.opt
      let restore .= '|let &'.opt.'='.val.''
    endif
  endfor

  " Set target buf options
  setlocal scrollbind nowrap nofoldenable
  silent! setlocal cursorbind

  " Save target buf position
  let top = line('w0') + &scrolloff
  let current = line('.')

  " Spawn codi
  exe g:codi#width.'vnew'
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
