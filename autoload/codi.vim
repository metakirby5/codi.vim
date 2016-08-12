" Display an error message
function! s:err(msg)
  echohl ErrorMsg | echom a:msg | echohl None
endfunction

" Returns the array of items not satisfying a:predicate.
" Optional error printed in the format of
" [msg]: [items].
function! s:all(predicate, required, ...)
  let s:missing = []
  for bin in a:required
    if a:predicate(bin) != 1
      call add(s:missing, bin)
    endif
  endfor
  if len(s:missing)
    if a:0
      call s:err(a:1.': '.join(s:missing, ', ').'.')
    endif
  endif
  return s:missing
endfunction

" Check for missing commands
let s:missing_deps = s:all(function('executable'), ['script', 'uname'])
if len(s:missing_deps)
  function! codi#run(...)
    return s:err(
          \ 'Codi requires these misssing commands: '
          \.join(s:missing_deps, ', ').'.')
  endfunction
  finish
endif

" Load resources
let s:interpreters = codi#load#interpreters()
let s:aliases = codi#load#aliases()
let s:updating = 0
let s:channels = {} " { ch_id: { bufnr: int, lines: [string] } }

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
    let s:script_post = '" /dev/null | cat'
  endif
else
  call s:err('Codi does not support Windows yet.')
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
  " === g:codi#update(async) ===
  " Async: TextChanged
  au TextChanged,TextChangedI * silent! call s:codi_update(1)
  " Sync: CursorHold
  au CursorHold,CursorHoldI * silent! call s:codi_update(0)

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
  if g:codi#autoclose && exists('b:codi_bufnr') && !s:updating
    " Remember width for when we respawn
    let b:codi_width = winwidth(bufwinnr(b:codi_bufnr))
    call s:codi_kill()
  endif
endfunction

function! s:codi_show()
  " If we saved a width, that means we hid codi earlier
  if g:codi#autoclose && exists('b:codi_width')
    call s:codi_spawn(&filetype)
    unlet b:codi_width
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
    " Shuffling is necessary because bdel triggers events
    let codi_bufnr = b:codi_bufnr
    unlet b:codi_bufnr
    exe 'keepjumps keepalt bdel '.codi_bufnr
  endif
endfunction

" Update the codi buf
function! s:codi_update(async)
  " Bail if no codi buf to act on
  if !exists('b:codi_bufnr') | return | endif

  let i = getbufvar(b:codi_bufnr, 'codi_interpreter')

  " Bail if async doesn't match up
  let async = has('job') && get(i, 'async', 1)
  if (has('job') && a:async) != async | return | endif

  let bufnr = bufnr('%')

  " Build input
  let input = join(getline('^', '$'), "\n")
  if has_key(i, 'rephrase')
    let input = i['rephrase'](input)
  endif

  " We use the magic sequence '' to get out of the REPL
  let input = input.''

  " Build the command
  let cmd = get(i, 'env', '').' '.s:script_pre.i['bin'].s:script_post

  " Async or sync
  if async
    let job = job_start(cmd, {
          \ 'callback': 'codi#__callback',
          \ 'close_cb': 'codi#__close_cb' })
    let ch = job_getchannel(job)

    " Save the associated bufnr
    let s:channels[ch_info(ch)['id']] = { 'bufnr': bufnr, 'lines': [] }

    " Send the input
    call ch_sendraw(ch, input)
  else
    call s:codi_handle_done(bufnr, system(cmd, input))
  endif

endfunction

" Callback to handle output
function! codi#__callback(ch, msg)
  call add(s:channels[ch_info(a:ch)['id']]['lines'], a:msg)
endfunction

" Callback to finish data gathering
function! codi#__close_cb(ch)
  let data = s:channels[ch_info(a:ch)['id']]
  silent! return s:codi_handle_done(data['bufnr'], join(data['lines'], "\n"))
endfunction

" Handle finished bin output
function! s:codi_handle_done(bufnr, output)
  " Save for later
  let ret_bufnr = bufnr('%')

  " Go to target buf
  exe 'keepjumps keepalt buf '.a:bufnr
  let s:updating = 1
  let codi_winwidth = winwidth(bufwinnr(b:codi_bufnr))
  let num_lines = line('$')

  " So we can jump back later
  let top = line('w0') + &scrolloff
  let line = line('.')
  let col = col('.')

  " So we can syncbind later
  keepjumps normal! gg

  " Go to codi buf
  exe 'keepjumps keepalt buf '.b:codi_bufnr
  setlocal modifiable
  let i = b:codi_interpreter

  " We then strip out some crap characters from script
  let output = substitute(substitute(a:output,
        \ '\|', '', 'g'), '\(^\|\n\)\(\^D\)\+', '\1', 'g')

  " If bsd, we need to get rid of inputted lines
  if s:bsd
    let output = join(split(output, "\n")[num_lines:], "\n")
  " If not bsd, we need to add line breaks
  else
    " Use a loop to handle ^ achors
    let result = []
    for l in split(output, "\n")
      while match(l, i['prompt']) != -1
        let subbed = substitute(l, i['prompt'], '\0'."\n", '')
        let [matched, l] = split(subbed, "\n", 1)
        call add(result, matched)
      endwhile
      call add(result, l)
    endfor
    let output = join(result, "\n")
  endif

  " Preprocess
  if has_key(i, 'preprocess')
    let output = i['preprocess'](output)
  endif

  " Unless raw, parse for propmt
  " Basic algorithm, for all lines:
  "   If we hit a prompt,
  "     If we have already passed the first prompt, record our taken line.
  "     Otherwise, note that we have passed the first prompt.
  "   Else,
  "     If we have passed the first prompt,
  "       If the line has no leading whitespace (usually stacktraces),
  "         Save the line as taken.
  if !g:codi#raw
    let result = []      " Overall result list
    let passed_first = 0 " Whether we have passed the first prompt
    let taken = ''       " What to print at the prompt

    " Iterate through all lines
    for l in split(output, "\n")
      " If we hit a prompt
      if match(l, i['prompt']) != -1
        " If we have passed the first prompt
        if passed_first
          " Record what was taken (needs to be at least one character)
          call add(result, len(taken) ? taken : ' ')
          let taken = ''
        else
          let passed_first = 1
        endif
      else
        " If we have passed the first prompt and it's content worth taking
        if passed_first && match(l, '^\S') != -1
          let taken = l
        endif
      endif
    endfor

    " Only take last num_lines of lines
    let lines = join(result[:num_lines - 1], "\n")
  else
    let lines = output
  endif

  " Read the result into the codi buf
  1,$d _ | 0put =lines
  exe 'setlocal textwidth='.codi_winwidth
  if g:codi#rightalign
    1,$right
  endif

  " Syncbind codi buf
  keepjumps normal! G"_ddgg
  syncbind
  setlocal nomodifiable

  " Restore target buf position
  exe 'keepjumps keepalt buf '.b:codi_target_bufnr
  exe 'keepjumps '.top
  keepjumps normal! zt
  keepjumps call cursor(line, col)
  let s:updating = 0

  " Go back to original buf
  exe 'keepjumps keepalt buf '.ret_bufnr
endfunction

function! s:codi_spawn(filetype)
  try
    " Requires s: scope because of FP issues
    let s:interpreter = s:interpreters[
          \ get(s:aliases, a:filetype, a:filetype)]
  " If interpreter not found...
  catch /E71\(3\|6\)/
    if empty(a:filetype)
      return s:err('Cannot run Codi with empty filetype.')
    else
      return s:err('No Codi interpreter for '.a:filetype.'.')
    endif
  endtry

  " Error checking
  let interpreter_str = 'Codi interpreter for '.a:filetype

  " Check if required keys present
  function! s:interpreter_has_key(key)
    return has_key(s:interpreter, a:key)
  endfunction
  if len(s:all(function('s:interpreter_has_key'),
        \ ['bin', 'prompt'],
        \ interpreter_str.' requires these missing keys'))
        \| return | endif

  " Check if bin present
  if !executable(s:interpreter['bin'])
      return s:err(interpreter_str.' requires '.s:interpreter['bin'].'.')
  endif

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
        \.(g:codi#rightsplit ? '' : ' leftabove ')
        \.(exists('b:codi_width') ? b:codi_width : g:codi#width).'vnew'
  setlocal filetype=codi
  exe 'setlocal syntax='.a:filetype
  let b:codi_target_bufnr = bufnr
  let b:codi_leave = restore
  let b:codi_interpreter = s:interpreter

  " Return to target split
  keepjumps keepalt wincmd p
  let b:codi_bufnr = bufnr('$')
  silent! return s:codi_update(get(s:interpreter, 'async', 1))
endfunction

" Main function
function! codi#run(bang, ...)
  " Handle arg
  if a:0
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
