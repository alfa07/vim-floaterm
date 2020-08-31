" vim:sw=2:
" ============================================================================
" FileName: terminal.vim
" Author: voldikss <dyzplus@gmail.com>
" GitHub: https://github.com/voldikss
" ============================================================================

let s:channel_map = {}
let s:is_win = has('win32') || has('win64')

function! s:on_floaterm_close(callback, job, data, ...) abort
  let bufnr = bufnr('%')
  if getbufvar(bufnr, '&filetype') != 'floaterm'
    return
  endif
  let winopts = getbufvar(bufnr, 'floaterm_winopts', {})
  let autoclose = get(winopts, 'autoclose', 0)
  if (autoclose == 1 && a:data == 0) || (autoclose == 2) || (a:callback isnot v:null)
    call floaterm#window#hide_floaterm(bufnr)
    try
      execute bufnr . 'bdelete!'
    catch
    endtry
    doautocmd BufDelete   "call lightline#update()
  endif
  if a:callback isnot v:null
    call a:callback(a:job, a:data, 'exit')
  endif
endfunction

function! floaterm#terminal#open(bufnr, cmd, jobopts, winopts) abort
  " for vim's popup, must close popup can we open and jump to a new window
  if !has('nvim')
    call floaterm#window#hide_floaterm(bufnr('%'))
  endif

  " change to root directory
  if !empty(g:floaterm_rootmarkers)
    let dest = floaterm#path#get_root()
    if dest !=# ''
      call floaterm#path#chdir(dest)
    endif
  endif

  if a:bufnr > 0
    call floaterm#window#open(a:bufnr, a:winopts)
    return
  endif

  if has('nvim')
    let bufnr = nvim_create_buf(v:false, v:true)
    call floaterm#buflist#add(bufnr)
    let a:jobopts.on_exit = function('s:on_floaterm_close', [get(a:jobopts, 'on_exit', v:null)])
    let winid = floaterm#window#open(bufnr, a:winopts)
    call nvim_set_current_win(winid)
    let ch = termopen(a:cmd, a:jobopts)
    let s:channel_map[bufnr] = ch
  else
    let a:jobopts.exit_cb = function('s:on_floaterm_close', [get(a:jobopts, 'on_exit', v:null)])
    if has_key(a:jobopts, 'on_exit')
      unlet a:jobopts.on_exit
    endif
    if has('patch-8.1.2080')
      let a:jobopts.term_api = 'floaterm#util#edit'
    endif
    let a:jobopts.hidden = 1
    let bufnr = term_start(a:cmd, a:jobopts)
    call floaterm#buflist#add(bufnr)
    let job = term_getjob(bufnr)
    let s:channel_map[bufnr] = job_getchannel(job)
    let winid = floaterm#window#open(bufnr, a:winopts)
  endif
  return bufnr
endfunction

function! floaterm#terminal#open_existing(bufnr) abort
  let winnr = bufwinnr(a:bufnr)
  if winnr > -1
    execute winnr . 'hide'
  endif
  let winopts = getbufvar(a:bufnr, 'floaterm_winopts', {})
  call floaterm#terminal#open(a:bufnr, '', {}, winopts)
endfunction

function! floaterm#terminal#send(bufnr, cmds) abort
  let ch = get(s:channel_map, a:bufnr, v:null)
  if empty(ch) || empty(a:cmds)
    return
  endif
  if has('nvim')
    call add(a:cmds, '')
    call chansend(ch, a:cmds)
    let curr_winnr = winnr()
    let ch_winnr = bufwinnr(a:bufnr)
    if ch_winnr > 0
      noautocmd execute ch_winnr . 'wincmd w'
      noautocmd execute 'normal! G'
    endif
    noautocmd execute curr_winnr . 'wincmd w'
  else
    let newline = s:is_win ? "\r\n" : "\n"
    call ch_sendraw(ch, join(a:cmds, newline) . newline)
  endif
endfunction

function! floaterm#terminal#get_bufnr(termname) abort
  return bufnr('floaterm://' . a:termname)
endfunction


function! floaterm#terminal#kill(bufnr) abort
  call floaterm#window#hide_floaterm(a:bufnr)
  if has('nvim')
    let jobid = getbufvar(a:bufnr, '&channel')
    if jobwait([jobid], 0)[0] == -1
      call jobstop(jobid)
    endif
  else
    let job = term_getjob(a:bufnr)
    if job_status(job) !=# 'dead'
      call job_stop(job)
    endif
  endif
  if bufexists(a:bufnr)
    execute a:bufnr . 'bwipeout!'
  endif
endfunction
