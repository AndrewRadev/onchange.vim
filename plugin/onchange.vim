if exists('g:loaded_onchange') || &cp
  finish
endif

let g:loaded_onchange = '0.0.1' " version number
let s:keepcpo = &cpo
set cpo&vim

if !exists('g:onchange_debug')
  let g:onchange_debug = 0
endif

function! s:UndoState()
  let tree = undotree()

  let undo_state = {
        \ 'current_seq_cur':   tree.seq_cur,
        \ 'previous_seq_cur':  tree.seq_cur,
        \ 'current_save_cur':  tree.save_cur,
        \ 'previous_save_cur': tree.save_cur,
        \ }

  function! undo_state.Undoing()
    return self.current_seq_cur < self.previous_seq_cur
  endfunction

  function! undo_state.Saving()
    return self.current_save_cur > self.previous_save_cur
  endfunction

  function! undo_state.Update()
    let tree = undotree()

    let self.previous_seq_cur  = self.current_seq_cur
    let self.current_seq_cur   = tree.seq_cur
    let self.previous_save_cur = self.current_save_cur
    let self.current_save_cur  = tree.save_cur

    if g:onchange_debug
      echomsg "Undo state Update(): ".string(self)
    endif
  endfunction

  return undo_state
endfunction

function! s:Change()
  let change = {
        \ 'original_line':     '',
        \ 'original_position': [],
        \ 'new_line':          '',
        \ 'new_position':      [],
        \ }

  function change.OldState()
    call setline(line('.'), self.original_line)
    call setpos('.', self.original_position)
  endfunction

  function change.NewState()
    call setline(line('.'), self.new_line)
    call setpos('.', self.new_position)
  endfunction

  return change
endfunction

augroup onchange
  autocmd!

  autocmd BufRead,BufNew * let b:undo_state = s:UndoState()
  autocmd TextChanged * call s:TextChanged()
augroup END

function! s:TextChanged()
  " TODO (2013-12-31) doesn't seem to work with undo before save
  return

  if !&modifiable
    return
  endif

  call b:undo_state.Update()

  if b:undo_state.Undoing() || b:undo_state.Saving()
    return
  endif

  let change = s:Change()

  try
    let saved_view = winsaveview()

    let change.new_line     = getline('.')
    let change.new_position = getpos('.')
    undo
    let change.original_line     = getline('.')
    let change.original_position = getpos('.')
    redo
  finally
    call winrestview(saved_view)
  endtry

  if change.original_line != change.new_line
    let b:last_change = change
    try
      let saved_view = winsaveview()
      doautocmd User Onchange
      call change.NewState()
    finally
      call winrestview(saved_view)
    endtry
  endif
endfunction

function! s:ReplaceMotion(motion, text)
  try
    let saved_view = winsaveview()
    let register = s:DefaultRegister()

    let saved_register_text = getreg(register, 1)
    let saved_register_type = getregtype(register)

    call setreg(register, a:text, 'v')
    exec 'silent normal! '.a:motion.'"'.register.'p'
    silent normal! gv=

    call setreg(register, saved_register_text, saved_register_type)
  finally
    call winrestview(saved_view)
  endtry
endfunction

" Finds the configuration's default paste register based on the 'clipboard'
" option.
function! s:DefaultRegister()
  if &clipboard =~ 'unnamedplus'
    return '+'
  elseif &clipboard =~ 'unnamed'
    return '*'
  else
    return '"'
  endif
endfunction

" Specific implementation - HTML tags
augroup Onchange
  autocmd!

  autocmd User Onchange call s:ChangeClosingTag(b:last_change)
augroup END

" TODO (2013-04-28) If the change also touches other things, it doesn't work
function! s:ChangeClosingTag(change)
  let change = a:change
  let position = getpos('.')

  if search('<\zs\w\+\%#', 'bc', line('.')) <= 0
    return
  endif

  let new_tag = expand('<cword>')

  " go back to the old tag for a bit
  call change.OldState()
  let old_tag = expand('<cword>')

  let cursor = getpos('.')
  call search('<\zs\V'.old_tag, 'bc', line('.'))

  " jump to the closing tag
  normal %
  if search('</\zs\V'.old_tag, 'c', line('.')) <= 0
    call change.NewState()
    return
  endif

  " replace it with the new tag
  call s:ReplaceMotion('viw', new_tag)

  " go back to the original position
  call setpos('.', position)
  call search('<\zs\V'.old_tag, 'bc', line('.'))

  " replace this word with the new tag as well
  call s:ReplaceMotion('viw', new_tag)
endfunction

let &cpo = s:keepcpo
unlet s:keepcpo
