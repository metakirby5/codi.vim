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

" Get string or first element of list
function! s:first_str(o)
  try
    call join(a:o)
    return a:o[0]
  " Not a list
  catch E714
    return a:o
  " Empty list
  catch E684
    return ''
  endtry
endfunction

" Get string or whole list joined by spaces
function! s:whole_str(o)
  try
    return join(a:o, ' ')
  " Not a list
  catch E714
    return a:o
  endtry
endfunction

" Check if executable - can be array of strings or string
function! s:check_exec(bin)
  return executable(s:first_str(a:bin))
endfunction

" Check for missing commands
let s:missing_deps = s:all(function('s:check_exec'), ['script', 'uname'])
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
let s:nvim = has('nvim')
let s:async = !g:codi#sync && ((has('job') && has('channel')) || s:nvim)
let s:updating = 0
let s:codis = {} " { bufnr: { codi_bufnr, codi_width, codi_restore } }
let s:async_jobs = {} " { bufnr: job }
let s:async_data = {} " { id (nvim -> job, vim -> ch): { data } }
let s:magic = "\n\<cr>\<c-d>\<c-d>\<cr>" " to get out of REPL

" Detect what version of script to use based on OS
if has("unix")
  let s:uname = system("uname -s")
  if s:uname =~ "Darwin" || s:uname =~ "BSD"
    function! s:scriptify(bin)
      return 'script -q /dev/null '.a:bin
    endfunction
  else
    function! s:scriptify(bin)
      return 'script -qfec '.shellescape(a:bin, 1).' /dev/null'
    endfunction
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
  " Clean up when codi is closed
  au BufWinLeave * if exists('b:codi_target_bufnr')
        \| exe 'keepjumps keepalt buf! '.b:codi_target_bufnr
        \| call s:codi_kill()
        \| endif
augroup END

" Actions on all windows
augroup CODI_TARGET
  au!
  " === g:codi#update() ===
  " Instant
  if s:async && g:codi#autocmd == 'TextChanged'
    au TextChanged,TextChangedI * call s:codi_update()
  " 'updatetime'
  elseif g:codi#autocmd == 'CursorHold'
    au CursorHold,CursorHoldI * call s:codi_update()
  " Insert mode left
  elseif g:codi#autocmd == 'InsertLeave'
    au InsertLeave * call s:codi_update()
  " Defaults
  else
    " Instant
    if s:async
      au TextChanged,TextChangedI * call s:codi_update()
    " 'updatetime'
    else
      au CursorHold,CursorHoldI * call s:codi_update()
    endif
  endif

  " === g:codi#autoclose ===
  " Hide on buffer leave
  au BufWinLeave * call s:codi_hide()
  " Show on buffer return
  au BufWinEnter * call s:codi_show()
  " Kill on target quit
  au QuitPre * call s:codi_autoclose()
augroup END

" Gets the ID, no matter if ch is open or closed.
function! s:ch_get_id(ch)
  let id = substitute(a:ch, '^channel \(\d\+\) \(open\|closed\)$', '\1', '')
endfunction

" Stop the job and clear it from the process table.
function! s:stop_job_for_buf(buf, ...)
  try
    let job = s:async_jobs[a:buf]
    unlet s:async_jobs[a:buf]
  catch E716
    return
  endtry

  if s:nvim
    silent! call jobstop(job)
  else
    if a:0
      call job_stop(job, a:1)
    else
      call job_stop(job)
    end

    " Implicitly clears from process table.
    call job_status(job)
  endif
endfunction

" Utility to get bufnr.
function! s:nr_bufnr(...)
  if a:0
    if a:1 == '%' || a:1 == '$'
      return bufnr(a:1)
    else
      return a:1
    endif
  else
    return bufnr('%')
  endif
endfunction

" Get the codi dict for a bufnr.
" {} if doesn't exist.
function! s:get_codi_dict(...)
  return get(s:codis, s:nr_bufnr(a:0 ? a:1 : '%'), {})
endfunction

" Get a codi key for a buffer.
" a:1 = default, a:2 = buffer
" 0 if doesn't exist.
function! s:get_codi(key, ...)
  return get(s:get_codi_dict(a:0 > 1 ? a:2 : '%'), a:key, a:0 ? a:1 : 0)
endfunction

" Set a codi key for a buffer.
function! s:let_codi(key, val, ...)
  let bufnr = s:nr_bufnr(a:0 ? a:1 : '%')
  let d = s:get_codi_dict(bufnr)
  let d[a:key] = a:val

  " Set to our dict if it isn't already there
  if !has_key(s:codis, bufnr) | let s:codis[bufnr] = d | endif
endfunction

" Unset a codi key for a buffer.
function! s:unlet_codi(key, ...)
  let bufnr = s:nr_bufnr(a:0 ? a:1 : '%')
  let d = s:codis[bufnr]
  unlet d[a:key]

  " Unset the main key if it's empty
  if d == {} | unlet s:codis[bufnr] | endif
endfunction

function! s:codi_toggle(filetype)
  if s:get_codi('bufnr')
    return s:codi_kill()
  else
    return s:codi_spawn(a:filetype)
  endif
endfunction

function! s:codi_hide()
  let codi_bufnr = s:get_codi('bufnr')
  if g:codi#autoclose && codi_bufnr && !s:updating
    " Remember width for when we respawn
    call s:let_codi('width', winwidth(bufwinnr(codi_bufnr)))
    call s:codi_kill()
  endif
endfunction

function! s:codi_show()
  " If we saved a width, that means we hid codi earlier
  if g:codi#autoclose && s:get_codi('width')
    call s:codi_spawn(&filetype)
    call s:unlet_codi('width')
  endif
endfunction

function! s:codi_autoclose()
  if g:codi#autoclose
    return s:codi_kill()
  endif
endfunction

function! s:codi_kill()
  " If we already have a codi instance for the buffer, kill it
  let codi_bufnr = s:get_codi('bufnr')
  if codi_bufnr
    silent do User CodiLeavePre
    call s:unlet_codi('bufnr')
    exe s:get_codi('restore')
    exe 'keepjumps keepalt bdel! '.codi_bufnr
    silent do User CodiLeavePost
  endif
endfunction

" Trigger autocommands and silently update
function! s:codi_update()
  silent do User CodiUpdatePre
  silent call s:codi_do_update()

  " Only trigger post if sync
  if !s:async
    silent do User CodiUpdatePost
  endif
endfunction

" Update the codi buf
function! s:codi_do_update()
  " Bail if no codi buf to act on
  let codi_bufnr = s:get_codi('bufnr')
  if !codi_bufnr | return | endif

  let i = getbufvar(codi_bufnr, 'codi_interpreter')
  let bufnr = bufnr('%')

  " Build input
  let input = join(getline('^', '$'), "\n")
  if has_key(i, 'rephrase')
    let input = i['rephrase'](input)
  endif
  let input = input.s:magic

  " Build the command
  let cmd = s:scriptify(s:whole_str(i['bin']))

  " Async or sync
  if s:async
    " Spawn the job
    if s:nvim
      let job = jobstart(cmd, {
            \ 'on_stdout': function('s:codi_nvim_callback'),
            \ 'on_stderr': function('s:codi_nvim_callback'),
            \ })
      let id = job
    else
      let job = job_start(cmd, { 'callback': 'codi#__vim_callback' })
      let ch = job_getchannel(job)
      let id = s:ch_get_id(ch)
    endif

    " Kill previously running job if necessary
    call s:stop_job_for_buf(bufnr)

    " Save job-related information
    let s:async_jobs[bufnr] = job
    let s:async_data[id] = {
          \ 'bufnr': bufnr,
          \ 'lines': [],
          \ 'interpreter': i,
          \ 'expected': line('$'),
          \ 'received': 0,
          \ }

    " Send the input
    if s:nvim
      call jobsend(job, input)
    else
      call ch_sendraw(ch, input)
    endif
  else
    call s:codi_handle_done(bufnr, system(cmd, input))
  endif
endfunction

" Callback to handle output (nvim)
function! s:codi_nvim_callback(job_id, data, event)
  try
    for line in a:data
      call s:codi_handle_data(s:async_data[a:job_id], line)
    endfor
  catch E716
    " No-op if data isn't ready
  endtry
endfunction

" Callback to handle output (vim)
function! codi#__vim_callback(ch, msg)
  try
    call s:codi_handle_data(s:async_data[s:ch_get_id(a:ch)], a:msg)
  catch E716
    " No-op if data isn't ready
  endtry
endfunction

" Generalized output handler
function! s:codi_handle_data(data, msg)
  " Bail early if we're done
  if a:data['received'] > a:data['expected'] | return | endif

  let i = a:data['interpreter']

  " Preprocess early so we can properly detect prompts
  try
    let out = i['preprocess'](a:msg)
  catch E716
    let out = a:msg
  endtry

  for line in split(out, "\n")
    call add(a:data['lines'], line)

    " Count our prompts, and stop if we've reached the right amount
    if line =~ i['prompt']
      let a:data['received'] += 1
      if a:data['received'] > a:data['expected']
        call s:stop_job_for_buf(a:data['bufnr'])
        silent call s:codi_handle_done(
              \ a:data['bufnr'], join(a:data['lines'], "\n"))
        silent do User CodiUpdatePost
      endif
    endif
  endfor
endfunction

" Handle finished bin output
function! s:codi_handle_done(bufnr, output)
  " Save for later
  let ret_bufnr = bufnr('%')
  let ret_mode = mode()

  " Go to target buf
  exe 'keepjumps keepalt buf! '.a:bufnr
  let s:updating = 1
  let codi_bufnr = s:get_codi('bufnr')
  let codi_winwidth = winwidth(bufwinnr(codi_bufnr))
  let num_lines = line('$')

  " So we can jump back later
  let top = line('w0') + &scrolloff
  let line = line('.')
  let col = col('.')

  " So we can syncbind later
  exe "keepjumps normal! \<esc>gg"

  " Go to codi buf
  exe 'keepjumps keepalt buf! '.codi_bufnr
  setlocal modifiable
  let i = b:codi_interpreter

  " We then strip out some crap characters from script
  let output = substitute(substitute(a:output,
        \ "\<cr>".'\|'."\<c-h>", '', 'g'), '\(^\|\n\)\(\^D\)\+', '\1', 'g')

  " Preprocess if we didn't already
  if !s:async && has_key(i, 'preprocess')
    let result = []
    for line in split(output, "\n")
      call add(result, i['preprocess'](line))
    endfor
    let output = join(result, "\n")
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
      if l =~ i['prompt']
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
        if passed_first && l =~ '^\S'
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
  exe 'keepjumps keepalt buf! '.b:codi_target_bufnr
  exe 'keepjumps '.top
  keepjumps normal! zt
  keepjumps call cursor(line, col)
  let s:updating = 0

  " Go back to original buf
  exe 'keepjumps keepalt buf! '.ret_bufnr

  " Restore mode
  if ret_mode =~ '[vV]'
    keepjumps normal! gv
  elseif ret_mode =~ '[sS]'
    exe "keepjumps normal! gv\<c-g>"
  endif
endfunction

function! s:codi_spawn(filetype)
  try
    " Requires s: scope because of FP issues
    let s:i = s:interpreters[
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
    return has_key(s:i, a:key)
  endfunction
  if len(s:all(function('s:interpreter_has_key'),
        \ ['bin', 'prompt'],
        \ interpreter_str.' requires these missing keys'))
        \| return | endif

  " Check if bin present
  if !s:check_exec(s:i['bin'])
      return s:err(interpreter_str.' requires '.s:first_str(s:i['bin']).'.')
  endif

  call s:codi_kill()
  silent do User CodiEnterPre

  " Save bufnr
  let bufnr = bufnr('%')

  " Save settings to restore later
  let winnr = winnr()
  let restore = 'call s:unlet_codi("restore")'
  for opt in ['scrollbind', 'cursorbind', 'wrap', 'foldenable']
    if exists('&'.opt)
      let val = getwinvar(winnr, '&'.opt)
      let restore .= ' | call setwinvar('.winnr.', "&'.opt.'", '.val.')'
    endif
  endfor
  call s:let_codi('restore', restore)

  " Set target buf options
  setlocal scrollbind nowrap nofoldenable
  silent! setlocal cursorbind

  " Spawn codi
  exe 'keepjumps keepalt '
        \.(g:codi#rightsplit ? 'rightbelow' : ' leftabove ')
        \.(s:get_codi('width', g:codi#width)).'vnew'
  setlocal filetype=codi
  exe 'setlocal syntax='.a:filetype
  let b:codi_target_bufnr = bufnr
  let b:codi_interpreter = s:i

  " Return to target split and save codi bufnr
  keepjumps keepalt wincmd p
  call s:let_codi('bufnr', bufnr('$'))
  silent call s:codi_update()
  silent do User CodiEnterPost
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
