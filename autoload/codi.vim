" Display an error message
function! s:err(msg)
  echohl ErrorMsg | echom a:msg | echohl None
endfunction

" Check for missing commands
let s:missing_cmds = []
for bin in ['script', 'awk', 'uname']
  if executable(bin) != 1
    call add(s:missing_cmds, bin)
  endif
endfor
if !empty(s:missing_cmds)
  function! codi#start(...)
    return s:err(
          \ 'Codi requires these misssing commands: '
          \.join(s:missing_cmds, ', ').'.')
  endfunction
  finish
endif

" Command aliases
let s:sh_cat = "awk '{ print }'"

" Load resources
let s:codi_interpreters = codi#load#interpreters()
let s:codi_aliases = codi#load#aliases()
let s:codi_updating = 0

" Detect what version of script to use based on OS
if has("unix")
  let s:uname = system("uname -s")
  if s:uname =~ "Darwin" || s:uname =~ "BSD"
    let s:bsd = 1
    let s:script_pre = 'script -q /dev/null '
    let s:script_post = ''
  else
    let s:bsd = 0
    let s:script_pre = 'script -qfec "'
    let s:script_post = '" /dev/null'
  endif
endif

" Actions on codi
augroup CODI
  au!
  " Local options
  au FileType codi setlocal
        \ buftype=nofile bufhidden=hide nobuflisted
        \ nomodifiable nomodified
        \ nonu nornu nolist nomodeline nowrap
        \ statusline=\  nocursorline nocursorcolumn
        \ foldcolumn=0 nofoldenable winfixwidth
        \ scrollbind
        \ | noremap <buffer> <silent> q <esc>:q<cr>
        \ | silent! setlocal cursorbind
  " Clean up when codi is killed
  au BufWinLeave *
        \ if exists('b:codi_leave') | silent! exe b:codi_leave | endif
augroup END

" Actions on all windows
augroup CODI_TARGET
  au!
  " Update codi buf on buf change
  au CursorHold,CursorHoldI * silent! call s:codi_update()

  " === g:codi#autoclose ===
  " Hide on buffer leave
  au BufWinLeave * silent! call s:codi_hide()
  " Show on buffer return
  au BufWinEnter * silent! call s:codi_show()
  " Kill on target quit
  au QuitPre * silent! call s:codi_autoclose()
augroup END

function! s:codi_toggle(filetype)
  if exists('b:codi_bufnr')
    return s:codi_kill()
  else
    return s:codi_spawn(a:filetype)
  endif
endfunction

function! s:codi_hide()
  if g:codi#autoclose && exists('b:codi_bufnr') && !s:codi_updating
    silent! exe bufwinnr(b:codi_bufnr).'close'
  endif
endfunction

function! s:codi_show()
  if g:codi#autoclose && exists('b:codi_bufnr')
    return s:codi_spawn(&filetype)
  endif
endfunction

function! s:codi_autoclose()
  if g:codi#autoclose
    return s:codi_kill()
  endif
endfunction

function! s:codi_kill()
  " If we already have a codi instance for the buffer, kill it
  if exists('b:codi_bufnr')
    exe 'keepjumps keepalt bdel '.b:codi_bufnr
    unlet b:codi_bufnr
  endif
endfunction

" Update the codi buf
function! s:codi_update()
  " Bail if no codi buf to act on
  if !exists('b:codi_bufnr') | return | endif
  let s:codi_updating = 1
  let codi_winwidth = winwidth(bufwinnr(b:codi_bufnr))

  " Setup target buf
  let num_lines = line('$')
  let content = join(getline('^', '$'), "\n")

  " So we can jump back later
  let top = line('w0') + &scrolloff
  let line = line('.')
  let col = col('.')

  " So we can syncbind later
  keepjumps normal! gg

  " Setup codi buf
  exe 'keepjumps keepalt buf '.b:codi_bufnr
  setlocal modifiable

  " Execute our code by:
  "   - Using script with environment variables to simulate a tty on
  "     the interpreter, which will take...
  "   - our shell-escaped EOL-terminated code as input,
  "     which is piped through...
  "   - awk, to remove ^Ds, backspaces (^H), and carriage returns (^M)...
  "   - if the system is bsd, use awk to get rid of inputted lines...
  "   - if the system is not bsd, use awk to add line breaks...
  "   - any user-provided preprocess...
  "   - if raw isn't set, awk to only print the line right before a prompt...
  "     (searches for lines where the first character is not a space)
  "   - and read it all into the Codi buffer.
  let i = b:codi_interpreter
  let cmd = '1,$d _ | 0read !'
        \.get(i, 'rephrase', s:sh_cat).' <<< '.shellescape(content."", 1)
        \.' | '.get(i, 'env', '').' '.s:script_pre.i['bin'].s:script_post
        \.' | awk "{ gsub(/^\^D||/, \"\"); print }"'

  " If bsd, we need to get rid of inputted lines
  if s:bsd
    let cmd .= ' | awk "NR > '.num_lines.' { print }"'
  " If not bsd, we need to add line breaks
  else
    let cmd .= ' | awk "{ gsub(/'.i['prompt'].'/, \"&\n\"); print }"'
  endif

  let cmd .= ' | '.get(i, 'preprocess', s:sh_cat)

  " If the user wants raw, don't parse for prompt
  if !g:codi#raw
    let cmd .= ' | awk "{'
            \.'if (/'.i['prompt'].'/)'
              \.'{ if (x) { print taken; taken = \"\" } else { x = 1 } }'
            \.'else'
              \.'{ if (x && /^[^ \t\n\x0B\f\r]/) { taken = \$0 } }'
          \.'}"'
  endif

  exe cmd
  exe 'setlocal textwidth='.codi_winwidth
  if g:codi#rightalign
    1,$right
  endif

  " Teardown codi buf
  keepjumps normal! G"_ddgg
  syncbind
  setlocal nomodifiable

  " Teardown target buf
  exe 'keepjumps keepalt buf '.b:codi_target_bufnr
  exe 'keepjumps '.top
  keepjumps normal! zt
  keepjumps call cursor(line, col)
  let s:codi_updating = 0
endfunction

function! s:codi_spawn(filetype)
  try
    let interpreter = s:codi_interpreters[
          \ get(s:codi_aliases, a:filetype, a:filetype)]
  " If interpreter not found...
  catch E716
    if empty(a:filetype)
      return s:err('Cannot run Codi with empty filetype.')
    else
      return s:err('No Codi interpreter for '.a:filetype.'.')
    endif
  endtry

  " Error checking
  let interpreter_str = 'Codi interpreter for '.a:filetype
  let error = 0

  " Check if required keys present
  let missing_keys = []
  for key in ['bin', 'prompt']
    if !has_key(interpreter, key)
      call add(missing_keys, key)
    endif
  endfor
  if !empty(missing_keys)
    call s:err(
          \ interpreter_str.' requires these missing keys: '
          \.join(missing_keys, ', '))
    let error = 1
  endif

  " Check if bin present
  if has_key(interpreter, 'bin') && executable(interpreter['bin']) != 1
    call s:err(
          \ interpreter_str.' requires this missing command: '
          \.interpreter['bin'])
    let error = 1
  endif

  " Check if deps present
  let s:missing_deps = []
  for bin in get(interpreter, 'deps', [])
    if executable(bin) != 1
      call add(s:missing_deps, bin)
    endif
  endfor
  if !empty(s:missing_deps)
    call s:err(
          \ interpreter_str.' requires these misssing commands: '
          \.join(s:missing_deps, ', ').'.')
    let error = 1
  endif

  if error | return | endif

  call s:codi_kill()

  " Adapted from:
  " https://github.com/tpope/vim-fugitive/blob/master/plugin/fugitive.vim#L1988

  " Restore target buf options on codi close
  let bufnr = bufnr('%')
  let restore = 'keepjumps keepalt bdel'
        \.' | keepjumps keepalt buf '.bufnr
        \.' | unlet b:codi_bufnr'
  for opt in ['scrollbind', 'cursorbind', 'wrap', 'foldenable']
    if exists('&'.opt)
      exe 'let val = &'.opt
      let restore .= '| let &'.opt.'='.val.''
    endif
  endfor

  " Set target buf options
  setlocal scrollbind nowrap nofoldenable
  silent! setlocal cursorbind

  " Spawn codi
  exe 'keepjumps keepalt '
        \.(g:codi#rightsplit ? '' : ' leftabove ').g:codi#width.'vnew'
  setlocal filetype=codi
  exe 'setlocal syntax='.a:filetype
  let b:codi_target_bufnr = bufnr
  let b:codi_leave = restore
  let b:codi_interpreter = interpreter

  " Return to target split
  keepjumps keepalt wincmd p
  let b:codi_bufnr = bufnr('$')
  silent! return s:codi_update()
endfunction

" Main function
function! codi#run(bang, ...)
  " Handle arg
  if exists('a:1')
    " Double-bang case
    if a:bang && a:1 =~ '^!'
      " Slice off the bang
      let filetype = substitute(a:1[1:], '^\s*', '', '')
      let toggle = 1
    else
      let filetype = a:1
      let toggle = 0
    endif
  else
    let filetype = ''
    let toggle = 0
  endif

  " Grab filetype if not provided
  if empty(filetype)
    let filetype = &filetype
  else
    exe 'setlocal filetype='.filetype
  endif

  " Bang -> kill
  if a:bang && !toggle
    return s:codi_kill()
  endif

  if toggle
    return s:codi_toggle(filetype)
  else
    return s:codi_spawn(filetype)
  endif
endfunction
