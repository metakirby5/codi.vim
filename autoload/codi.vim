" Log a message
function! s:log(message)
  " Bail if not logging
  if g:codi#log ==# '' | return | endif

  " Grab stack trace not including log function
  let stacktrace = expand('<sfile>')
  let stacktrace = stacktrace[0:strridx(stacktrace, '..') - 1]

  " Remove everything except the last function
  let i = strridx(stacktrace, '..')
  if i != -1
    let fname = stacktrace[i + 2:]
  else
    " Strip 'function '
    let fname = stacktrace[9:]
  endif

  " Create timestamp with microseconds
  let seconds_and_microseconds = reltimestr(reltime())
  let decimal_i = stridx(seconds_and_microseconds, '.')
  let seconds = seconds_and_microseconds[:decimal_i - 1]
  let microseconds = seconds_and_microseconds[decimal_i + 1:]
  let timestamp = strftime('%T.'.microseconds, seconds)

  " Write to log file
  call writefile(['['.timestamp.'] '.fname.': '.a:message],
        \ g:codi#log, 'a')
endfunction

" Display an error message
function! s:err(msg)
  call s:log('ERROR: '.a:msg)
  echohl ErrorMsg | echom a:msg | echohl None
endfunction

" Version check - can't guarantee anything for < 704
if v:version < 704
  function! codi#run(...)
    return s:err('Codi requires Vim 7.4 or higher.')
  endfunction
  finish
endif

" Returns the array of items not satisfying a:predicate.
" Optional error printed in the format of
" [msg]: [items].
function! s:require(predicate, required, ...)
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
  " Check if a list.
  if type(a:o) is# v:t_list
    " Check if list is empty.
    if len(a:o) > 0
      return a:o[0]
    else
      return ''
    endif
  " Not a list.
  else
    return a:o
  endif
endfunction

" Check if executable - can be array of strings or string
function! s:check_exec(bin)
  return executable(s:first_str(a:bin))
endfunction

" Check for missing commands
let s:missing_deps = s:require(function('s:check_exec'), ['script', 'uname'])
if len(s:missing_deps) && !has('win32')
  function! codi#run(...)
    return s:err(
          \ 'Codi requires these missing commands: '
          \.join(s:missing_deps, ', ').'.')
  endfunction
  finish
endif

" Load resources
let s:interpreters = codi#load#interpreters()
let s:aliases = codi#load#aliases()
let s:nvim = has('nvim')
let s:virtual_text_namespace = has("nvim") && nvim_create_namespace("codi")
let s:async_ok = has('job') && has('channel') || s:nvim
let s:updating = 0
let s:codis = {} " { bufnr: { codi_bufnr, codi_width, codi_restore } }
let s:async_jobs = {} " { bufnr: job }
let s:async_data = {} " { id (nvim -> job, vim -> ch): { data } }
let s:magic = "\n\<cr>\<c-d>\<c-d>\<cr>" " to get out of REPL

" Store results for later consultation (for :CodiExpand)
let s:results = []

" Is virtual text enabled?
function! s:is_virtual_text_enabled()
  return s:nvim && g:codi#virtual_text
endfunction

" Shell escape on a list to make one string
function! s:shellescape_list(l)
  let result = []
  for arg in a:l
    call add(result, shellescape(arg, 1))
  endfor
  return join(result, ' ')
endfunction

" Detect what version of script to use based on OS
if has('unix')
  let s:uname = system('uname -s')
  if s:uname =~# 'Darwin' || s:uname =~# 'BSD'
    call s:log('Darwin/BSD detected, using `script -q /dev/null $bin`')
    function! s:scriptify(bin)
      " We need to keep the arguments plain
      return ['script', '-q', '/dev/null'] + a:bin
    endfunction
  else
    call s:log('Linux detected, using `script -qfec "$bin" /dev/null`')
    function! s:scriptify(bin)
      " We need to make bin one string argument
      let tmp_bin = '/tmp/cmd'
      call writefile([s:shellescape_list(a:bin)], tmp_bin)
      call setfperm(tmp_bin, 'rwx------')
      return ['script', '-qfec', tmp_bin, '/dev/null']
    endfunction
  endif
else
  call s:log ('Windows deteced, using')
endif

" Actions on codi
augroup CODI
  au!
  " Local options
  au FileType codi setlocal
        \ buftype=nofile bufhidden=hide nobuflisted
        \ nomodifiable nomodified
        \ nonu nornu nolist nomodeline nowrap
        \ statusline=\  nocursorline nocursorcolumn colorcolumn=
        \ foldcolumn=0 nofoldenable winfixwidth
        \ scrollbind
        \ | noremap <buffer> <silent> q <esc>:q<cr>
        \ | silent! setlocal cursorbind
        \ | silent! setlocal signcolumn=no
  " Clean up when codi is closed
  au BufWinLeave * if exists('b:codi_target_bufnr')
        \| exe 'keepjumps keepalt buf! '.b:codi_target_bufnr
        \| call s:codi_kill()
        \| endif
augroup END

" Actions on all windows
augroup CODI_TARGET
  au!
  " === g:codi#autoclose ===
  " Hide on buffer leave
  au BufWinLeave * call s:codi_hide()
  " Show on buffer return
  au BufWinEnter * call s:codi_show()
  " Kill on target quit
  au QuitPre * call s:codi_autoclose()
augroup END

" If list, return the same list
" Else, return an array containing just o
function! s:to_list(o)
  if type(a:o) == type([])
    return a:o
  else
    return [a:o]
  endif
endfunction

" Does a user autocmd if exists
function! s:user_au(au)
  call s:log('Doing autocommand '.a:au)
  if exists('#User#'.a:au)
    exe 'do <nomodeline> User '.a:au
  endif
endfunction

" If percent / float width, calculate based on buf width
" while respecting |winwidth|
" Else, return absolute width as given
function! s:pane_width()
  let width = s:get_opt('width')

  if type(width) == type(0)
    return width
  endif

  let buf_width  = winwidth(bufwinnr('%'))
  let pane_width = float2nr(round(buf_width * (width > 0.0 ? width : 0.0) / 100))

  return max([&winwidth, min([buf_width - &winwidth, pane_width])])
endfunction

" Gets an interpreter option, and if not available, global option.
" Pulls from get_codi('interpreter').
function! s:get_opt(option, ...)
  if a:0
    let i = s:get_codi('interpreter', {}, a:1)
  else
    let i = s:get_codi('interpreter', {})
  endif

  " Async is a special case
  if a:option ==# 'async'
    return !get(i, 'sync', g:codi#sync) && s:async_ok
  endif

  exe 'let default = g:codi#' . a:option
  return get(i, a:option, default)
endfunction

" Gets the ID, no matter if ch is open or closed.
function! s:ch_get_id(ch)
  let id = substitute(a:ch, '^channel \(\d\+\) \(open\|closed\)$', '\1', '')
endfunction

" Stop the job and clear it from the process table.
function! s:stop_job_for_buf(buf, ...)
  try
    let job = s:async_jobs[a:buf]
    unlet s:async_jobs[a:buf]
  catch /E716/
    return
  endtry

  call s:log('Stopping job for buffer '.a:buf)

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
    if a:1 ==# '%' || a:1 ==# '$'
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

" Preprocess (default + interpreter)
function! s:preprocess(text, ...)
  " Default pre-process
  let out = substitute(substitute(substitute(a:text,
        \ "\<cr>".'\|'."\<c-h>", '', 'g'),
        \ '\(^\|\n\)\(\^D\)\+', '\1', 'g'),
        \ "\<esc>".'\[?*[0-9;]*\a', '', 'g')
  if a:0 && has_key(a:1, 'preprocess')
    let out = a:1['preprocess'](out)
  endif
  return out
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
  if s:get_opt('autoclose') && codi_bufnr && !s:updating
    " Remember width for when we respawn
    call s:let_codi('width', winwidth(bufwinnr(codi_bufnr)))
    call s:codi_kill()
  endif
endfunction

function! s:codi_show()
  " If we saved a width, that means we hid codi earlier
  if s:get_opt('autoclose') && s:get_codi('width')
    call s:codi_spawn(&filetype)
    call s:unlet_codi('width')
  endif
endfunction

function! s:codi_autoclose()
  if s:get_opt('autoclose')
    return s:codi_kill()
  endif
endfunction

function! s:codi_kill()
  " If we already have a codi instance for the buffer, kill it
  let codi_bufnr = s:get_codi('bufnr')
  if codi_bufnr
    call s:user_au('CodiLeavePre')
    " Clear autocommands
    exe 'augroup CODI_TARGET_'.bufnr('%')
      au!
    augroup END
    exe s:get_codi('restore')
    call s:unlet_codi('interpreter')
    call s:unlet_codi('bufnr')
    exe 'keepjumps keepalt bdel! '.codi_bufnr
    call s:user_au('CodiLeavePost')
  endif
endfunction

" Trigger autocommands and silently update
function! codi#update()
  " Bail if no codi buf to act on except virtual text is enabled and available
  if !s:is_virtual_text_enabled() && !s:get_codi('bufnr') | return | endif

  call s:user_au('CodiUpdatePre')
  silent call s:codi_do_update()

  " Only trigger post if sync
  if !s:get_opt('async')
    call s:user_au('CodiUpdatePost')
  endif
endfunction

" Update the codi buf
function! s:codi_do_update()
  let codi_bufnr = s:get_codi('bufnr')
  let i = s:get_codi('interpreter')
  let bufnr = bufnr('%')

  " Build input
  let input = join(getline('^', '$'), "\n")
  if has_key(i, 'rephrase')
    let input = i['rephrase'](input)
  endif
  if has_key(i, 'quitcmd')
    let input = input."\n".i['quitcmd']."\n"
  else
    let input = input.s:magic
  endif

  " Build the command
  let cmd = g:codi#command_prefix + s:to_list(i['bin'])

  " The purpose of this is to make the REPL start from the buffer directory
  let opt_use_buffer_dir = s:get_opt('use_buffer_dir')
  if opt_use_buffer_dir
    let buf_dir = expand('%:p:h')
    if !s:nvim
      let cwd = getcwd()
      exe 'cd '.fnameescape(buf_dir)
    endif
  endif

  call s:log('Starting job for buffer '.bufnr)

  " Async or sync
  if s:get_opt('async')
    " Spawn the job
    if s:nvim
      let job_options = {
            \ 'pty': 1,
            \ 'on_stdout': function('s:codi_nvim_callback'),
            \ 'on_stderr': function('s:codi_nvim_callback'),
            \ 'env': {'SHELL': 'sh'}
            \}
      if opt_use_buffer_dir
        let job_options.cwd = buf_dir
      endif
      let job = jobstart(cmd, job_options)
      let id = job
    else
      let job = job_start(s:scriptify(cmd), { 
            \ 'callback': 'codi#__vim_callback', 
            \ 'env': {'SHELL': 'sh'}
            \})
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

    call s:log('[INPUT] '.input)
    call s:log('Expecting '.(line('$') + 1).' prompts')

    " Send the input
    if s:nvim
      call jobsend(job, input)
    else
      call ch_sendraw(ch, input)
    endif
  else
    call s:log("Async off")
    " Convert command to string
    call s:codi_handle_done(bufnr,
          \ system(s:shellescape_list(s:scriptify(cmd)), input))
  endif

  " Change back to original cwd to avoid side effects
  if opt_use_buffer_dir && !s:nvim
    exe 'cd '.fnameescape(cwd)
  endif
endfunction

" Callback to handle output (nvim)
let s:nvim_async_lines = {} " to hold partially built lines
function! s:codi_nvim_callback(job_id, data, event)

  " Initialize storage
  if !has_key(s:nvim_async_lines, a:job_id)
    let s:nvim_async_lines[a:job_id] = ''
  endif

  for line in a:data
    let s:nvim_async_lines[a:job_id] .= line

    " If we hit a newline, we're ready to handle the data
    if s:nvim_async_lines[a:job_id][-1:] == "\<cr>"
      let input = s:nvim_async_lines[a:job_id]
      let s:nvim_async_lines[a:job_id] = ''
      try
        call s:codi_handle_data(s:async_data[a:job_id], input)
      catch /E716/
        " No-op if data isn't ready
      endtry
    endif
  endfor
endfunction

" Callback to handle output (vim)
function! codi#__vim_callback(ch, msg)
  try
    call s:codi_handle_data(s:async_data[s:ch_get_id(a:ch)], a:msg)
  catch /E716/
    " No-op if data isn't ready
  endtry
endfunction

" Generalized output handler
function! s:codi_handle_data(data, msg)
  " Bail early if we're done
  if a:data['received'] > a:data['expected'] | return | endif
  let i = a:data['interpreter']

  " Preprocess early so we can properly detect prompts
  let out = s:preprocess(a:msg, i)

  for line in split(out, "\n")
    call s:log('[DATA] '.line)
    call add(a:data['lines'], line)

    " Count our prompts, and stop if we've reached the right amount
    if line =~ i['prompt']
      call s:log('Matched prompt')
      let a:data['received'] += 1
      if a:data['received'] > a:data['expected']
        call s:log('All prompts received')
        call s:stop_job_for_buf(a:data['bufnr'])
        if s:is_virtual_text_enabled()
          silent call s:virtual_text_codi_handle_done(
                \ a:data['bufnr'], join(a:data['lines'], "\n"))
        else
          silent call s:codi_handle_done(
                \ a:data['bufnr'], join(a:data['lines'], "\n"))
        endif
        call s:user_au('CodiUpdatePost')
      endif
    endif
  endfor
endfunction

" Handle finished bin output
function! s:codi_handle_done(bufnr, output)
  " Save for later
  let ret_bufnr = bufnr('%')
  let ret_mode = mode()
  let ret_winview = winsaveview()

  " Go to target buf
  exe 'keepjumps keepalt buf! '.a:bufnr
  let s:updating = 1
  let codi_bufnr = s:get_codi('bufnr')
  let codi_winwidth = winwidth(bufwinnr(codi_bufnr))
  let interpreter = s:get_codi('interpreter')
  let num_lines = line('$')

  " So we can syncbind later
  let winview = winsaveview()
  silent! exe "keepjumps normal! \<esc>gg"

  " Go to codi buf
  exe 'keepjumps keepalt buf! '.codi_bufnr
  setlocal modifiable

  let lines = s:preprocess_and_parse(a:output, interpreter, num_lines)

  " Read the result into the codi buf
  1,$d _ | 0put =lines
  exe 'setlocal textwidth='.codi_winwidth
  if s:get_opt('rightalign', b:codi_target_bufnr)
    1,$right
  endif

  " Syncbind codi buf
  keepjumps normal! G"_ddgg
  syncbind
  setlocal nomodifiable

  " Restore target buf position
  exe 'keepjumps keepalt buf! '.b:codi_target_bufnr
  keepjumps normal! ggzt
  call winrestview(winview)
  exe "normal! \<esc>"
  let s:updating = 0

  " Go back to original buf
  exe 'keepjumps keepalt buf! '.ret_bufnr

  " Restore mode and position
  if ret_mode =~? '[vV]'
    keepjumps normal! gv
  elseif ret_mode =~? '[sS]'
    exe "keepjumps normal! gv\<c-g>"
  endif
  call winrestview(ret_winview)
endfunction

function! s:preprocess_and_parse(output, interpreter, num_lines)
  " Preprocess if we didn't already
  if !s:get_opt('async', b:codi_target_bufnr)
    let result = []
    for line in split(a:output, "\n")
      call add(result, s:preprocess(line, a:interpreter))
    endfor
    let output = join(result, "\n")
  else
    let output = a:output
  endif

  " Unless raw, parse for prompt
  " Basic algorithm, for all lines:
  "   If we hit a prompt,
  "     If we have already passed the first prompt, record our taken line.
  "     Otherwise, note that we have passed the first prompt.
  "   Else,
  "     If we have passed the first prompt,
  "       If the line has no leading whitespace (usually stacktraces),
  "         Save the line as taken.
  if !s:get_opt('raw', b:codi_target_bufnr)
    let result = []      " Overall result list
    let passed_first = 0 " Whether we have passed the first prompt
    let taken = ''       " What to print at the prompt

    let outtbl = []      " Output table [line: [output of repl]]
    let out_lines = []   " Lines for the current prompt

    " Iterate through all lines
    for l in split(output, "\n")
      " If we hit a prompt
      if l =~ a:interpreter['prompt']
        " If we have passed the first prompt
        if passed_first
          " Record what was taken, empty if nothing happens
          call add(result, len(taken) ? taken : '')
          call add(outtbl, out_lines)
          let taken = ''
          let out_lines = []
        else
          let passed_first = 1
        endif
      else
        if passed_first
          call add(out_lines, l)
          " If we have passed the first prompt and it's content worth taking
          if l =~? '^\S'
            let taken = l
          endif
        endif
      endif
    endfor

    " Only take last num_lines of lines
    let lines = join(result[:a:num_lines - 1], "\n")
    let s:results = outtbl
  else
    let lines = output
  endif

  return lines
endfunction

function! s:virtual_text_codi_handle_done(bufnr, output)
  let s:updating = 1
  let interpreter = s:get_codi('interpreter')
  let num_lines = line('$')
  let result = s:preprocess_and_parse(a:output, interpreter, num_lines)
  call s:nvim_codi_output_to_virtual_text(a:bufnr, result)
endfunction

function! s:nvim_codi_clear_virtual_text()
  call nvim_buf_clear_namespace(bufnr('%'),
   \ s:virtual_text_namespace, 0, -1)
endfunction

function! s:nvim_codi_output_to_virtual_text(bufnr, lines)
  " Iterate through the result and print using virtual text
  let i = 0
  for line in split(a:lines, "\n", 1)
    if len(line)
      let extmarks = s:get_codi("extmarks")
      let opts = { 'virt_text': [[g:codi#virtual_text_prefix . line, "CodiVirtualText"]] }
      if exists('g:codi#virtual_text_pos')
        if type(g:codi#virtual_text_pos) == v:t_number
          let opts.virt_text_win_col = g:codi#virtual_text_pos
        else
          let opts.virt_text_pos = g:codi#virtual_text_pos
        endif
      endif
      if has_key(extmarks, i)
        let opts.id = extmarks[i]
      endif

      let extmarks[i] = nvim_buf_set_extmark(a:bufnr, s:virtual_text_namespace, i, 0, opts)
      call s:let_codi("extmarks", extmarks)
    else
      call nvim_buf_clear_namespace(a:bufnr, s:virtual_text_namespace, i, i+1)
    endif
    let i += 1
  endfor
endfunction

" Return the interpreter to use far the given filetype or null if not found.
" If null is returned, an error is logged.
function! s:get_interpreter(ft)
  try
    return s:interpreters[get(s:aliases, a:ft, a:ft)]
  catch /E71\(3\|6\)/
    if empty(a:ft)
      call s:err('Cannot run Codi with empty filetype.')
    else
      call s:err('No Codi interpreter for '.a:ft.'.')
    endif
    return v:null
  endtry
endfunction

function! s:codi_spawn(filetype)
  let i = s:get_interpreter(a:filetype)
  if i is v:null
    return
  endif

  " Error checking
  let interpreter_str = 'Codi interpreter for '.a:filetype

  " Check if required keys present
  let s:spawn_interpreter = i
  function! s:interpreter_has_key(key)
    return has_key(s:spawn_interpreter, a:key)
  endfunction
  if len(s:require(function('s:interpreter_has_key'),
        \ ['bin', 'prompt'],
        \ interpreter_str.' requires these missing keys'))
        \| return | endif

  " Check if bin present
  if !s:check_exec(i['bin'])
      return s:err(interpreter_str.' requires '.s:first_str(i['bin']).'.')
  endif

  call s:codi_kill()
  call s:user_au('CodiEnterPre')

  " Store the interpreter we're using
  call s:let_codi('interpreter', i)

  call s:let_codi('extmarks', {})

  " Save bufnr
  let bufnr = bufnr('%')

  " Save settings to restore later
  let winnr = winnr()
  let restore = 'call s:unlet_codi("restore")'
  let restore .= ' | call s:unlet_codi("extmarks")'
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

  " Set up autocommands
  let opt_async = s:get_opt('async')
  let opt_autocmd = s:get_opt('autocmd')
  if opt_autocmd !=# 'None'
    exe 'augroup CODI_TARGET_'.bufnr
      au!
      " === g:codi#update() ===
      " Instant
      if opt_async && opt_autocmd ==# 'TextChanged'
        au TextChanged,TextChangedI <buffer> call codi#update()
      " 'updatetime'
      elseif opt_autocmd ==# 'CursorHold'
        au CursorHold,CursorHoldI <buffer> call codi#update()
      " Insert mode left
      elseif opt_autocmd ==# 'InsertLeave'
        au InsertLeave <buffer> call codi#update()
      " Defaults
      else
        " Instant
        if opt_async
          au TextChanged,TextChangedI <buffer> call codi#update()
        " 'updatetime'
        else
          au CursorHold,CursorHoldI <buffer> call codi#update()
        endif
      endif
    augroup END
  endif

  " Spawn codi buffer if virtual text is disabled
  if !s:is_virtual_text_enabled()
    exe 'keepjumps keepalt '
          \.(s:get_opt('rightsplit') ? 'rightbelow' : 'leftabove').' '
          \.(s:get_codi('width', s:pane_width())).'vnew'
    setlocal filetype=codi
    exe 'setlocal syntax='.a:filetype
  endif
  let b:codi_target_bufnr = bufnr

  " Return to target split and save codi bufnr
  keepjumps keepalt wincmd p
  if !s:is_virtual_text_enabled()
    call s:let_codi('bufnr', bufnr('$'))
  endif
  silent call codi#update()
  call s:user_au('CodiEnterPost')
endfunction

" Main function
function! codi#run(bang, ...)
  " Handle arg
  if a:0
    " Double-bang case
    if a:bang && a:1 =~? '^!'
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

  if s:is_virtual_text_enabled()
    call s:nvim_codi_clear_virtual_text()
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

" Command-line complete function 
function! codi#complete(arg_lead, cmd_line, cursor_pos)
    " Get all built-in interpreters and user-defined interpreters
    let candidates = getcompletion('', 'filetype') + keys(g:codi#interpreters)
    " Filter matches according to the prefix
    if a:arg_lead !=# ''
        let candidates = filter(candidates, 'v:val[:len(a:arg_lead) - 1] == a:arg_lead')
    endif
    return sort(candidates)
endfunction

function! codi#new(...)
  let ft = a:0 ? a:1 : &filetype

  if s:get_interpreter(ft) is v:null 
    return
  endif

  noswapfile hide enew
  setlocal buftype=nofile
  setlocal bufhidden=hide

  call codi#run(0, ft)
endfunction

lua << EOF
function _G.codi_select(interpreters)
  local filetypes = {}
  for k, v in pairs(interpreters) do
    filetypes[#filetypes + 1] = k
  end

  vim.ui.select(filetypes, {
    prompt = "Codi Filetype",
  }, function(ft)
    vim.fn["codi#new"](ft)
  end)
end

function _G.codi_expand_popup(lines)
  local col = vim.g["codi#virtual_text_pos"]
  local posx
  if type(col) == "number" then
    posx = col + #vim.g["codi#virtual_text_prefix"]
  elseif col == "right_align" then
    posx = vim.fn.winwidth(0)
  else
    posx = #vim.fn.getline(".") + #vim.g["codi#virtual_text_prefix"]
  end

  vim.lsp.util.open_floating_preview(lines, "", {
    wrap = false,
    border = "rounded",
    offset_x = posx - vim.fn.wincol() + 1,
  })
end
EOF

function! codi#select()
  call v:lua.codi_select(s:interpreters)
endfunction

function! codi#expand()
  let lineidx = line(".") - 1
  if lineidx >= len(s:results)
    return
  endif
  let lines = s:results[lineidx]
  if len(lines) ==  0
    return
  endif

  if has("nvim")
    call v:lua.codi_expand_popup(lines)
  else
    " TODO add vim support here (Probably using :h popup)
  endif
endfunction

