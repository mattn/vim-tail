function! s:append_line(expr, text) abort
  if bufnr(a:expr) == -1
    return
  endif
  let mode = mode()
  let oldnr = winnr()
  let winnr = bufwinnr(a:expr)
  if oldnr != winnr
    if winnr == -1
      silent exec "sp ".escape(bufname(bufnr(a:expr)), ' \')
    else
      exec winnr.'wincmd w'
    endif
  endif
  setlocal modifiable | call append('$', a:text) | setlocal nomodifiable
  let pos = getpos('.')
  let pos[1] = line('$')
  let pos[2] = 9999
  call setpos('.', pos)
  if oldnr != winnr
    if winnr == -1
      silent hide
    endif
  endif

  exec oldnr.'wincmd w'
  if mode =~# '[sSvV]'
    silent! normal gv
  endif
  if mode !~# '[cC]'
    redraw
  endif
endfunction

function! s:append_part(expr, text) abort
  let mode = mode()
  let oldnr = winnr()
  let winnr = bufwinnr('__TERMINAL__')
  if oldnr != winnr
    if winnr == -1
      silent exec "sp ".escape(bufname(bufnr(a:expr)), ' \')
    else
      exec winnr.'wincmd w'
    endif
  endif
  let text = a:text
  if a:text =~ "\<c-l>.*$"
    let text = substitute(text, ".*\<c-l>", '', 'g')
    %d _
    redraw
  endif
  let text = substitute(text, "\x1b\[[0-9;]*[a-zA-Z]", "", "g")
  call setline('.', split(getline('.') . text, '\r\?\n', 1))
  let pos = getpos('.')
  let pos[1] = line('$')
  let pos[2] += len(a:text)
  call setpos('.', pos)
  let b:line = getline('.')
  if oldnr != winnr
    if winnr == -1
      silent hide
    endif
  endif

  exec oldnr.'wincmd w'
  if mode =~# '[sSvV]'
    silent! normal gv
  endif
  if mode !~# '[cC]'
    redraw
  endif
endfunction

function! s:initialize_tail(job, handle) abort
  let wn = bufwinnr('__TERMINAL__')
  if wn != -1
    if wn != winnr()
      exe wn 'wincmd w'
    endif
  else
    silent exec 'rightbelow new __TERMINAL__'
    set filetype=__TERMINAL__
  endif
  silent! %d _
  setlocal buftype=nofile bufhidden=wipe noswapfile
  setlocal nomodified
  setlocal nomodifiable
  augroup Terminal
    au!
    autocmd BufWipeout <buffer> call s:terminate()
  augroup END
  let b:job = a:job
  let b:handle = a:handle
  nnoremap <buffer> <c-c> :<c-u>call job_stop(b:job)<cr>
  nnoremap <buffer> i :<c-u>call <SID>sendinput()<cr>
  wincmd p
  set lazyredraw
endfunction

function! s:initialize_terminal(job, handle) abort
  let wn = bufwinnr('__TERMINAL__')
  if wn != -1
    if wn != winnr()
      exe wn 'wincmd w'
    endif
  else
    silent exec 'rightbelow new __TERMINAL__'
    set filetype=__TERMINAL__
  endif
  silent! %d _
  setlocal buftype=nofile bufhidden=wipe noswapfile
  augroup Terminal
    au!
    autocmd BufWipeout <buffer> call s:terminate()
    autocmd InsertCharPre <buffer> call s:sendkey(v:char)
  augroup END
  let b:job = a:job
  let b:handle = a:handle
  let b:line = ''
  inoremap <buffer> <silent> <c-c> <C-R>=<SID>sendcc()<cr>
  inoremap <buffer> <silent> <cr> <C-R>=<SID>sendcr()<cr>
  inoremap <buffer> <silent> <tab> <C-R>=<SID>sendkey("\t")<cr>
  inoremap <buffer> <silent> <bs> <C-R>=<SID>sendkey("\08")<cr>
  startinsert!
  set lazyredraw
endfunction

function! s:terminate() abort
  let wn = bufwinnr('__TERMINAL__')
  if wn == -1
    return
  endif
  if wn != winnr()
    exe wn 'wincmd w'
  endif
  if exists('b:handle')
    silent! call ch_close(b:handle)
    unlet b:handle
  endif
  if exists('b:job')
    silent! call job_stop(b:job, 'kill')
    unlet b:job
  endif
  augroup Terminal
    au!
  augroup END
  wincmd p
endfunction

function! s:sendinput(c) abort
  let line = input('INPUT: ')
  silent! call ch_sendraw(b:handle, line . "\n")
endfunction

function! s:sendkey(c) abort
  silent! call ch_sendraw(b:handle, a:c, {'callback': ''})
  if !has('win32')
    let v:char = ''
  endif
  return ''
endfunction

function! s:sendcr() abort
  if has('win32')
    silent! call setline('.', b:line)
    let b:line = ''
  endif
  silent! call ch_sendraw(b:handle, "\n", {'callback': ''})
  return ''
endfunction

function! s:sendcc() abort
  call job_stop(b:job)
  return ''
endfunction

function! terminal#linecb(id, msg)
  for line in split(a:msg, '\r\?\n')
    call s:append_line('__TERMINAL__', line)
  endfor
endfunction

function! terminal#partcb_out(id, msg)
  let msg = iconv(a:msg, 'char', &encoding)
  let msg = substitute(msg, "\r", "", "g")
  call s:append_part('__TERMINAL__', msg)
  if exists('b:job')
      call job_status(b:job)
  endif
endfunction

function! terminal#exitcb(job, code)
  call s:append_line('__TERMINAL__', string(a:job) . " with exit code " . string(a:code))
  augroup Terminal
    au!
  augroup END
  call feedkeys("\<ESC>", "t")
endfunction

function! terminal#quickfix(id, msg)
  for line in split(a:msg, '\r\?\n')
    silent! caddexpr line
  endfor
endfunction

function! terminal#tail_file(arg) abort
  let job = job_start('tail -f ' . shellescape(a:arg))
  call job_setoptions(job, {'exit_cb': 'terminal#exitcb', 'stoponexit': 'kill'})
  let handle = job_getchannel(job)
  call ch_setoptions(handle, {'out_cb': 'terminal#linecb', 'mode': 'raw'})
  call s:initialize_tail(job, handle)
endfunction

function! terminal#tail_cmd(arg) abort
  let job = job_start(a:arg)
  call job_setoptions(job, {'exit_cb': 'terminal#exitcb', 'stoponexit': 'kill'})
  let handle = job_getchannel(job)
  call ch_setoptions(handle, {'out_cb': 'terminal#linecb', 'err_cb': 'terminal#linecb', 'mode': 'raw'})
  call s:initialize_tail(job, handle)
endfunction

function! terminal#quickfix_cmd(arg) abort
  let job = job_start(a:arg)
  call job_setoptions(job, {'exit_cb': 'terminal#exitcb', 'stoponexit': 'kill'})
  let handle = job_getchannel(job)
  call ch_setoptions(handle, {'out_cb': 'terminal#linecb', 'err_cb': 'terminal#linecb', 'mode': 'raw'})
  copen
  wincmd p
endfunction

function! terminal#term(arg) abort
  let cmd = a:arg
  if empty(cmd)
    let cmd = has('win32') ? 'cmd' : 'bash --login -i'
  endif
  let job = job_start(cmd)
  call job_setoptions(job, {'exit_cb': 'terminal#exitcb', 'stoponexit': 'kill'})
  let handle = job_getchannel(job)
  call ch_setoptions(handle, {'out_cb': 'terminal#partcb_out', 'err_cb': 'terminal#partcb_out', 'mode': 'raw'})
  call s:initialize_terminal(job, handle)
endfunction
