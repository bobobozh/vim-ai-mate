call vim_ai_config#load()

let s:plugin_root = expand('<sfile>:p:h:h')
let s:complete_py = s:plugin_root . "/py/complete.py"
let s:chat_py = s:plugin_root . "/py/chat.py"
let s:roles_py = s:plugin_root . "/py/roles.py"

" remembers last command parameters to be used in AIRedoRun
let s:last_is_selection = 0
let s:last_firstline = 1
let s:last_lastline = 1
let s:last_instruction = ""
let s:last_command = ""
let s:last_config = {}

let s:scratch_buffer_name = ">>> AI chat"

" =============================================================================
" 窗口管理
" =============================================================================

" Configures ai-chat scratch window.
function! vim_ai#MakeScratchWindow() abort
  let l:keep_open = g:vim_ai.chat.window.keep_open
  if l:keep_open && bufexists(s:scratch_buffer_name)
    execute "buffer " . s:scratch_buffer_name
    return
  endif
  setlocal buftype=nofile
  setlocal noswapfile
  setlocal ft=aichat
  if l:keep_open
    setlocal bufhidden=hide
  else
    setlocal bufhidden=wipe
  endif
  if bufexists(s:scratch_buffer_name)
    " spawn another window if chat already exist
    let l:index = 2
    while bufexists(s:scratch_buffer_name . " " . l:index)
      let l:index += 1
    endwhile
    execute "file " . s:scratch_buffer_name . " " . l:index
  else
    execute "file " . s:scratch_buffer_name
  endif
endfunction

function! s:OpenChatWindow(open_conf)
  let l:preset = get(g:vim_ai_open_chat_presets, a:open_conf, a:open_conf)
  execute l:preset
endfunction

function! s:ReuseOrCreateChatWindow(config)
  if &filetype != 'aichat'
    " reuse chat in active window or tab
    let l:chat_win_ids = win_findbuf(bufnr(s:scratch_buffer_name))
    if !empty(l:chat_win_ids)
      call win_gotoid(l:chat_win_ids[0])
      return
    endif

    " reuse .aichat file on the same tab
    let buffer_list_tab = tabpagebuflist(tabpagenr())
    let buffer_list_tab = filter(buffer_list_tab, 'getbufvar(v:val, "&filetype") ==# "aichat"')
    if len(buffer_list_tab) > 0
      call win_gotoid(win_findbuf(buffer_list_tab[0])[0])
      return
    endif

    " reuse any .aichat buffer in the session
    let buffer_list = []
    for i in range(tabpagenr('$'))
      call extend(buffer_list, tabpagebuflist(i + 1))
    endfor
    let buffer_list = filter(buffer_list, 'getbufvar(v:val, "&filetype") ==# "aichat"')
    if len(buffer_list) > 0
      call win_gotoid(win_findbuf(buffer_list[0])[0])
      return
    endif

    " open new chat window if no active buffer found
    let l:open_conf = g:vim_ai.chat.window.preset
    call s:OpenChatWindow(l:open_conf)
  endif
endfunction

" =============================================================================
" 提示词构建
" =============================================================================

function! s:MakeSelectionPrompt(selection, instruction, config)
  let l:selection = ""
  if a:instruction == ""
    let l:selection = a:selection
  elseif !empty(a:selection)
    let l:boundary = get(a:config, 'selection_boundary', '')
    if l:boundary != "" && match(a:selection, l:boundary) == -1
      let l:selection = l:boundary . "\n" . a:selection . "\n" . l:boundary
    else
      let l:selection = a:selection
    endif
  endif
  return l:selection
endfunction

function! s:MakePrompt(selection, instruction, config)
  let l:instruction = trim(a:instruction)
  let l:delimiter = l:instruction != "" && a:selection != "" ? ":\n" : ""
  let l:selection = s:MakeSelectionPrompt(a:selection, l:instruction, a:config)
  return join([l:instruction, l:delimiter, l:selection], "")
endfunction

" =============================================================================
" 选区处理
" =============================================================================

let s:is_handling_paste_mode = 0

function! s:set_paste(config)
  if !&paste && get(a:config, 'paste_mode', 0)
    let s:is_handling_paste_mode = 1
    setlocal paste
  endif
endfunction

function! s:set_nopaste(config)
  if s:is_handling_paste_mode
    setlocal nopaste
    let s:is_handling_paste_mode = 0
  endif
endfunction

function! s:GetSelectionOrRange(is_selection, ...)
  if a:is_selection
    return s:GetVisualSelection()
  else
    return trim(join(getline(a:1, a:2), "\n"))
  endif
endfunction

function! s:SelectSelectionOrRange(is_selection, ...)
  if a:is_selection
    execute "normal! gv"
  else
    execute 'normal!' . a:1 . 'GV' . a:2 . 'G'
  endif
endfunction

function! s:GetVisualSelection()
  let [line_start, column_start] = getpos("'<")[1:2]
  let [line_end, column_end] = getpos("'>")[1:2]
  let lines = getline(line_start, line_end)
  if len(lines) == 0
    return ''
  endif
  " The exclusive mode means that the last character of the selection area is not included in the operation scope.
  let lines[-1] = lines[-1][: column_end - (&selection == 'inclusive' ? 1 : 2)]
  let lines[0] = lines[0][column_start - 1:]
  return join(lines, "\n")
endfunction

" =============================================================================
" 核心命令实现
" =============================================================================

" Complete/Edit prompt
function! vim_ai#AIRun(config, ...) range abort
  let l:config = vim_ai_config#ExtendDeep(g:vim_ai_complete, a:config)
  let l:instruction = a:0 > 0 ? a:1 : ""
  " l:is_selection used in Python script
  if a:0 > 1
    let l:is_selection = a:2
  else
    let l:is_selection = g:vim_ai_is_selection_pending &&
          \ a:firstline == line("'<") && a:lastline == line("'>")
  endif

  let l:selection = s:GetSelectionOrRange(l:is_selection, a:firstline, a:lastline)
  let l:prompt = s:MakePrompt(l:selection, l:instruction, l:config)

  let s:last_command = "complete"
  let s:last_config = a:config
  let s:last_instruction = l:instruction
  let s:last_is_selection = l:is_selection
  let s:last_firstline = a:firstline
  let s:last_lastline = a:lastline

  let l:cursor_on_empty_line = empty(getline('.'))
  try
    call s:set_paste(l:config)
    if l:cursor_on_empty_line
      execute "normal! " . a:lastline . "GA"
    else
      execute "normal! " . a:lastline . "Go"
    endif
    execute "py3file " . s:complete_py
    execute "normal! " . a:lastline . "G"
  finally
    call s:set_nopaste(l:config)
  endtry
endfunction

" Start and answer the chat
function! vim_ai#AIChatRun(uses_range, config, ...) range abort
  let l:config = vim_ai_config#ExtendDeep(g:vim_ai_chat, a:config)
  let l:instruction = ""
  " l:is_selection used in Python script
  if a:uses_range
    let l:is_selection = g:vim_ai_is_selection_pending &&
          \ a:firstline == line("'<") && a:lastline == line("'>")
    let l:selection = s:GetSelectionOrRange(l:is_selection, a:firstline, a:lastline)
  else
    let l:is_selection = 0
    let l:selection = ''
  endif
  try
    call s:set_paste(l:config)

    call s:ReuseOrCreateChatWindow(l:config)

    let l:prompt = ""
    if a:0 > 0 || a:uses_range
      let l:instruction = a:0 > 0 ? a:1 : ""
      let l:prompt = s:MakePrompt(l:selection, l:instruction, l:config)
    endif

    let s:last_command = "chat"
    let s:last_config = a:config

    execute "py3file " . s:chat_py
  finally
    call s:set_nopaste(l:config)
  endtry
endfunction

" Start a new chat
function! vim_ai#AINewChatRun(...) abort
  let l:preset = a:0 > 0 ? a:1 : g:vim_ai.chat.window.preset
  call s:OpenChatWindow(l:preset)
  call vim_ai#AIChatRun(0, {})
endfunction

" Repeat last AI command
function! vim_ai#AIRedoRun() abort
  undo
  if s:last_command ==# "complete"
    exe s:last_firstline.",".s:last_lastline . "call vim_ai#AIRun(s:last_config, s:last_instruction, s:last_is_selection)"
  elseif s:last_command ==# "chat"
    call vim_ai#AIChatRun(0, s:last_config)
  endif
endfunction

" =============================================================================
" 补全函数
" =============================================================================

function! vim_ai#RoleCompletion(A,L,P) abort
  execute "py3file " . s:roles_py
  call map(l:role_list, '"/" . v:val')
  return filter(l:role_list, 'v:val =~ "^' . a:A . '"')
endfunction

function! vim_ai#WindowPresetCompletion(A,L,P) abort
  return filter(keys(g:vim_ai_open_chat_presets), 'v:val =~ "^' . a:A . '"')
endfunction

function! vim_ai_config#ExtendDeep(defaults, override) abort
  let l:result = copy(a:defaults)
  for [l:key, l:value] in items(a:override)
    if type(get(l:result, l:key)) == v:t_dict && type(l:value) == v:t_dict
      let l:result[l:key] = vim_ai_config#ExtendDeep(l:result[l:key], l:value)
    else
      let l:result[l:key] = l:value
    endif
  endfor
  return l:result
endfunction
