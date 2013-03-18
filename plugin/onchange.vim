if exists('g:loaded_onchange') || &cp
  finish
endif

let g:loaded_onchange = '0.0.1' " version number
let s:keepcpo = &cpo
set cpo&vim

function! s:Change()
  return {
        \ 'editing_mode':      '',
        \ 'original_line':     -1,
        \ 'original_position': [],
        \ 'new_line':          -1,
        \ 'new_position':      [],
        \ }
endfunction

let g:last_change = s:Change()

augroup InsertTracking
  autocmd!

  autocmd InsertEnter * call s:InsertEnter(v:insertmode)
  autocmd InsertLeave * call s:InsertLeave()
augroup END

nnoremap c :silent call <SID>InsertEnter('c')<cr>
nnoremap C :silent call <SID>InsertEnter('C')<cr>

let g:insert_enter_mode = ''

"foo bar three more

function! s:InsertEnter(mode)
  if g:last_change.editing_mode =~ '[cC]'
    " it was already called from a mapping, bail out
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

function! s:ChangeClosingTag(change)
  let change = a:change

  try
    let saved_view = winsaveview()

    if search('<\zs\w\+\%#', 'bc', line('.')) <= 0
      return
    endif

    let new_tag = expand('<cword>')
    call setline(line('.'), change.original_line)
    let old_tag = expand('<cword>')
    call setline(line('.'), change.new_line)

    " go back to the old tag for a bit
    let cursor = getpos('.')
    call s:ReplaceMotion('viw', old_tag)
    call setpos('.', cursor)
    call search('<\zs\w\+', 'bc', line('.'))

    " jump to the closing tag
    normal %
    if search('</\zs\w\+', 'c', line('.')) <= 0
      call setline(line('.'), change.new_line)
      return
    endif

    " replace it with the new tag
    call s:ReplaceMotion('viw', new_tag)

    " go back to the previous position
    call winrestview(saved_view)
    call search('<\zs\w\+\%#', 'bc', line('.'))

    " replace this word with the new tag as well
    call s:ReplaceMotion('viw', new_tag)
  finally
    call winrestview(saved_view)
  endtry
endfunction

let &cpo = s:keepcpo
unlet s:keepcpo
