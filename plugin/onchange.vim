" Upon pressing "i", "o" and the like, the s:InsertEnter function is invoked
" by the InsertEnter autocommand.
"
" The "c" and "C" mappings are handled differently. They are remapped to call
" s:InsertEnter, and when insert mode is entered, another InsertEnter is
" called which needs to be ignored.
"
" Potential Bug: c + <c-c> + i
" Potential Bug: c + <esc><esc> + i
"

if exists('g:loaded_onchange') || &cp
  finish
endif

let g:loaded_onchange = '0.0.1' " version number
let s:keepcpo = &cpo
set cpo&vim

function! s:Change()
  let change = {
        \ 'editing_mode':      '',
        \ 'original_line':     -1,
        \ 'original_position': [],
        \ 'new_line':          -1,
        \ 'new_position':      [],
        \ }

  function change.OldState()
    call setpos('.', self.original_position)
    call setline(line('.'), self.original_line)
  endfunction

  function change.NewState()
    call setpos('.', self.new_position)
    call setline(line('.'), self.new_line)
  endfunction

  return change
endfunction

let g:last_change = s:Change()

augroup InsertTracking
  autocmd!

  autocmd InsertEnter * call s:InsertEnter(v:insertmode)
  autocmd InsertLeave * call s:InsertLeave()
augroup END

nnoremap c :silent call <SID>InsertEnter('c')<cr>
nnoremap C :silent call <SID>InsertEnter('C')<cr>

function! s:InsertEnter(mode)
  if a:mode !~ '[cC]' && g:last_change.editing_mode =~ '[cC]'
    " it was already called from a mapping, bail out
    let g:last_change.editing_mode = ''
    return
  endif

  let g:last_change = s:Change()

  let g:last_change.original_line     = getline('.')
  let g:last_change.original_position = getpos('.')
  let g:last_change.editing_mode      = a:mode

  if g:last_change.editing_mode =~ '[cC]'
    " called from a mapping
    let c_mapping = a:mode
    let typeahead = s:GetTypeahead()
    call feedkeys(c_mapping, 'n')
    call feedkeys(typeahead)
  else
    " called from an autocommand
  endif
endfunction

function! s:InsertLeave()
  let g:last_change.new_line     = getline('.')
  let g:last_change.new_position = getpos('.')

  silent doautocmd User Onchange

  let g:last_change.editing_mode = ''
endfunction

function! s:GetTypeahead()
  let typeahead = ''

  let char = getchar(0)
  while char != 0
    let typeahead .= nr2char(char)
    let char = getchar(0)
  endwhile

  return typeahead
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

  autocmd User Onchange call s:ChangeClosingTag(g:last_change)
augroup END

" TODO (2013-04-28) If the change also touches other things, it doesn't work
function! s:ChangeClosingTag(change)
  let change = a:change

  try
    let saved_view = winsaveview()

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

    " go back to the previous position
    call winrestview(saved_view)
    call search('<\zs\V'.old_tag, 'bc', line('.'))

    " replace this word with the new tag as well
    call s:ReplaceMotion('viw', new_tag)
  finally
    call winrestview(saved_view)
  endtry
endfunction

let &cpo = s:keepcpo
unlet s:keepcpo
