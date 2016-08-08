" Display a warning message
function! s:warn(msg)
  echohl WarningMsg | echom a:msg | echohl None
endfunction

" Check for missing commands
let s:missing_cmds = []
for bin in ['script', 'cat', 'head', 'tail', 'tr', 'sed', 'awk']
  if executable(bin) != 1
    call add(s:missing_cmds, bin)
  endif
endfor
if !empty(s:missing_cmds)
  function! codi#start(...)
    call s:warn(
          \ 'Codi requires these misssing commands: '
          \.join(s:missing_cmds, ', ').'.')
  endfunction
  finish
endif

" Detect what version of script to use based on OS
if has("unix")
  let s:uname = system("uname -s")
  if s:uname =~ "Darwin" || s:uname =~ "BSD"
    let s:script_pre = 'script -q /dev/null '
    let s:script_post = ''
  else
    let s:script_pre = 'script -qfec "'
    let s:script_post = '" /dev/null'
  endif
endif

" Default interpreters
let s:codi_interpreters = {
      \ 'python': {
          \ 'bin': 'python',
          \ 'prompt': '^(>>>|\.\.\.) ',
          \ 'preprocess': 'head -n-1',
          \ },
      \ 'javascript': {
          \ 'bin': 'node',
          \ 'env': 'NODE_DISABLE_COLORS=1',
          \ 'prompt': '^(>|\.\.\.) ',
          \ 'preprocess': 'sed "s/\[\(1G\|0J\|3G\)//g"',
          \ },
      \ 'haskell': {
          \ 'bin': 'ghci',
          \ 'prompt': '^Prelude> ',
          \ 'preprocess':
            \ 'sed "s/\(\[?1[hl]\|E\)//g" | tr "" "\n" | cut -c2-',
          \ },
      \ 'ruby': {
          \ 'bin': 'irb',
          \ 'prompt': '^irb\([[:alnum:]]+\):[[:digit:]]{3,}:[[:digit:]]+. ',
          \ 'preprocess':
            \ 'sed "s/^=> //g"',
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
  "   - Using script with environment variables to simulate a tty on
  "     the interpreter, which will take...
  "   - our shell-escaped EOL-terminated code as input,
  "     which is piped through...
  "   - tr, to remove those backspaces (^H) and carriage returns (^M)...
  "   - tail, to get rid of the lines we input...
  "   - any user-provided preprocess...
  "   - if raw isn't set...
  "     - awk, to only print the line right before a prompt...
  "     - tail again, to remove the first blank line...
  "   - and read it all into the Codi buffer.
  let i = b:codi_interpreter
  let cmd = 'read !'
        \.get(i, 'env', '').' '.s:script_pre.i['bin'].s:script_post
        \.' <<< '.shellescape(content."").' | sed "s/^\^D//"'
        \.' | tr -d ""'
        \.' | tail -n+'.(num_lines + 1)
        \.' | '.get(i, 'preprocess', 'cat')

  " If the user wants raw, don't parse for prompt
  if !g:codi#raw
    let cmd .= ' | awk "{'
            \.'if (/'.i['prompt'].'/)'
              \.'{ print taken; taken = \"\" }'
            \.'else'
              \.'{ if (\$0) { taken = \$0 } }'
          \.'}" | tail -n+2'
  endif

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
      call s:warn('No Codi interpreter for '.filetype.'.')
    endif
    return
  endtry

  " Error checking
  let interpreter_str = 'Codi interpreter for '.filetype
  let error = 0

  " Check if required keys present
  let missing_keys = []
  for key in ['bin', 'prompt']
    if !has_key(interpreter, key)
      call add(missing_keys, key)
    endif
  endfor
  if !empty(missing_keys)
    call s:warn(
          \ interpreter_str.' requires these missing keys: '
          \.join(missing_keys, ', '))
    let error = 1
  endif

  " Check if bin present
  if has_key(interpreter, 'bin') && executable(interpreter['bin']) != 1
    call s:warn(
          \ interpreter_str.' requires this missing command: '
          \.interpreter['bin'])
    let error = 1
  endif

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
