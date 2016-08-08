" Default interpreters
let s:codi_interpreters = {
      \ 'python': {
          \ 'bin': 'python',
          \ 'prompt': '^(>>>|\.\.\.) ',
          \ },
      \ 'javascript': {
          \ 'bin': 'node',
          \ 'env': 'NODE_DISABLE_COLORS=1',
          \ 'prompt': '^(>|\.\.\.) ',
          \ 'prepipe': 'sed "s/\[\(1G\|0J\|3G\)//g"',
          \ },
      \ 'haskell': {
          \ 'bin': 'ghci',
          \ 'prompt': '^Prelude> ',
          \ 'prepipe':
            \ 'sed "s/\(\[?1[hl]\|E\)//g" | tr "" "\n" | cut -c2-',
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
  " TODO fix this
  " if g:codi#autoclose
  "   au BufWinLeave * silent! call s:codi_end()
  " endif
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
  let b:codi_interpreting = 1
  let pos = getcurpos()
  let num_lines = line('$')
  let content = join(getline('^', '$'), "\n")

  " Setup codi buf
  exe 'buf '.b:codi_bufnr
  setlocal modifiable
  let codi_pos = getcurpos()
  normal! gg_dG

  " Execute our code by:
  "   - Using script with environment variables to simulate a tty on...
  "   - The interpreter, which will take our shell-escaped EOL-terminated
  "     code as input, which is piped through...
  "   - tr, to remove those backspaces (^H) and carriage returns (^M)...
  "   - tail, to get rid of the lines we input...
  "   - any user-provided prepipe...
  "   - if raw isn't set...
  "     - awk, to only print the line right before a prompt...
  "     - tail again, to remove the first blank line...
  "   - any user-provided postpipe
  " TODO linux script support
  let i = b:codi_interpreter
  let cmd = 'read !'
        \.get(i, 'env', '').' script -q /dev/null '
        \.i['bin'].' <<< '.shellescape(content."").' | sed "s/^\^D//"'
        \.' | tr -d ""'
        \.' | tail -n+'.(num_lines + 1)
        \.' | '.get(i, 'prepipe', 'cat')

  " If the user wants raw, don't parse for prompt
  if !g:codi#raw
    let cmd .= ' | awk "{'
            \.'if (/'.i['prompt'].'/)'
              \.'{ print taken; taken = \"\" }'
            \.'else'
              \.'{ if (\$0) { taken = \$0 } }'
          \.'}" | tail -n+2'
  endif

  let cmd .= ' | '.get(i, 'postpipe', 'cat')

  exe cmd

  " Teardown codi buf
  normal! gg_dd
  call setpos('.', codi_pos)
  setlocal nomodifiable

  " Teardown target buf
  buf #
  call setpos('.', pos)
  unlet b:codi_interpreting
endfunction

function! s:codi_end()
  " Bail if interpreting in progress
  if exists('b:codi_interpreting') | return | endif

  " If we already have a codi instance for the buffer, kill it
  if exists('b:codi_bufnr')
    exe 'bdel '.b:codi_bufnr
    unlet b:codi_bufnr
  endif
endfunction

" Main function
function! codi#start(...)
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

  call s:codi_end()

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
