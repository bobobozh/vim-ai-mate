" =============================================================================
" Vim-AI 核心模块
" 纯 Vimscript 实现，基于 curl + job 的异步流式请求
" =============================================================================

let s:plugin_root = expand('<sfile>:p:h:h')

" 上次命令状态（用于 AIRedo）
let s:last_command = ''
let s:last_config = {}
let s:last_instruction = ''
let s:last_is_selection = 0
let s:last_firstline = 1
let s:last_lastline = 1

" 当前请求的上下文 id
let s:current_ctx_id = ''

let s:scratch_buffer_name = ">>> AI chat"

" =============================================================================
" 窗口管理
" =============================================================================

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

function! s:ReuseOrCreateChatWindow()
  if &filetype != 'aichat'
    let l:chat_win_ids = win_findbuf(bufnr(s:scratch_buffer_name))
    if !empty(l:chat_win_ids)
      call win_gotoid(l:chat_win_ids[0])
      return
    endif

    let buffer_list_tab = tabpagebuflist(tabpagenr())
    let buffer_list_tab = filter(buffer_list_tab, 'getbufvar(v:val, "&filetype") ==# "aichat"')
    if len(buffer_list_tab) > 0
      call win_gotoid(win_findbuf(buffer_list_tab[0])[0])
      return
    endif

    let buffer_list = []
    for i in range(tabpagenr('$'))
      call extend(buffer_list, tabpagebuflist(i + 1))
    endfor
    let buffer_list = filter(buffer_list, 'getbufvar(v:val, "&filetype") ==# "aichat"')
    if len(buffer_list) > 0
      call win_gotoid(win_findbuf(buffer_list[0])[0])
      return
    endif

    let l:open_conf = g:vim_ai.chat.window.preset
    call s:OpenChatWindow(l:open_conf)
  endif
endfunction

" =============================================================================
" 选区处理
" =============================================================================

let s:is_handling_paste_mode = 0

function! s:SetPaste(paste_mode)
  if !&paste && a:paste_mode
    let s:is_handling_paste_mode = 1
    setlocal paste
  endif
endfunction

function! s:SetNoPaste()
  if s:is_handling_paste_mode
    setlocal nopaste
    let s:is_handling_paste_mode = 0
  endif
endfunction

function! s:GetSelectionOrRange(is_selection, first_ln, last_ln)
  if a:is_selection
    return s:GetVisualSelection()
  else
    return trim(join(getline(a:first_ln, a:last_ln), "\n"))
  endif
endfunction

function! s:GetVisualSelection()
  let [lstart, cstart] = getpos("'<")[1:2]
  let [lend, cend] = getpos("'>")[1:2]
  let lines = getline(lstart, lend)
  if len(lines) == 0
    return ''
  endif
  let lines[-1] = lines[-1][: cend - (&selection == 'inclusive' ? 1 : 2)]
  let lines[0] = lines[0][cstart - 1:]
  return join(lines, "\n")
endfunction

" =============================================================================
" 提示词构建
" =============================================================================

function! s:MakeSelectionPrompt(selection, instruction, config)
  if a:instruction == ''
    return a:selection
  elseif !empty(a:selection)
    let l:boundary = get(a:config, 'selection_boundary', '')
    if l:boundary != '' && match(a:selection, l:boundary) == -1
      return l:boundary . "\n" . a:selection . "\n" . l:boundary
    endif
  endif
  return a:selection
endfunction

function! s:MakePrompt(selection, instruction, config)
  let l:instruction = trim(a:instruction)
  let l:delimiter = l:instruction != '' && a:selection != '' ? ":\n" : ''
  let l:selection = s:MakeSelectionPrompt(a:selection, l:instruction, a:config)
  return join([l:instruction, l:delimiter, l:selection], '')
endfunction

" =============================================================================
" 文本渲染辅助
" =============================================================================

function! s:NeedInsertBeforeCursor(is_selection)
  if !a:is_selection
    return 0
  endif
  let l:pos = getpos("'<")[1:2]
  return l:pos[1] == 1
endfunction

" =============================================================================
" 补全渲染状态
" =============================================================================

let s:complete_state = {'started': 0, 'insert_before': 0, 'bufnr': 0}

" =============================================================================
" AI 补全命令
" =============================================================================

function! vim_ai#AIRun(config, ...) dict range abort
  let l:config = vim_ai_config#ExtendDeep(g:vim_ai_complete, a:config)
  let l:instruction = a:0 > 0 ? a:1 : ""

  if a:0 > 1
    let l:is_selection = a:2
  else
    let l:is_selection = g:vim_ai_is_selection_pending &&
          \ a:firstline == line("'<") && a:lastline == line("'>")
  endif

  let l:selection = s:GetSelectionOrRange(l:is_selection, a:firstline, a:lastline)

  " 解析角色
  let [l:prompt, l:role_opts] = vim_ai_roles#ParsePrompt(l:instruction)
  let l:prompt = s:MakePrompt(l:selection, l:prompt, l:config)

  " 保存上次状态
  let s:last_command = "complete"
  let s:last_config = a:config
  let s:last_instruction = l:instruction
  let s:last_is_selection = l:is_selection
  let s:last_firstline = a:firstline
  let s:last_lastline = a:lastline

  " 合并选项
  let l:api_opts = {
        \ 'model': get(l:config, 'model', g:vim_ai.api.model),
        \ 'endpoint_url': get(l:config, 'endpoint_url', g:vim_ai.api.endpoint_url),
        \ 'temperature': get(l:config, 'temperature', g:vim_ai.api.temperature),
        \ 'top_p': get(g:vim_ai.api, 'top_p', 0.8),
        \ 'timeout': get(g:vim_ai.api, 'timeout', 30),
        \ }
  let l:api_opts = extend(l:api_opts, get(l:role_opts, 'options_default', {}))
  let l:api_opts = extend(l:api_opts, get(l:role_opts, 'options_complete', {}))

  " 定位光标
  let l:cursor_on_empty_line = empty(getline('.'))
  call s:SetPaste(get(l:config, 'paste_mode', 0))
  if l:cursor_on_empty_line
    execute "normal! " . a:lastline . "GA"
  else
    execute "normal! " . a:lastline . "Go"
  endif

  " 构建消息
  let l:messages = [
        \ {'role': 'system', 'content': 'You are a helpful assistant.'},
        \ {'role': 'user', 'content': l:prompt},
        \ ]

  " 渲染状态
  let s:complete_state.started = 0
  let s:complete_state.insert_before = s:NeedInsertBeforeCursor(l:is_selection)
  let s:complete_state.bufnr = bufnr('%')
  echo 'Completing...'

  " 发送异步请求
  let s:current_ctx_id = vim_ai_http#ChatStream(
        \ l:api_opts, l:messages,
        \ function('s:OnCompleteChunk'),
        \ function('s:OnCompleteDone'),
        \ function('s:OnCompleteError')
        \ )
endfunction

function! s:OnCompleteChunk(text)
  if !a:text
    return
  endif
  if !s:complete_state.started && !trim(a:text)
    return
  endif
  let s:complete_state.started = 1

  if s:complete_state.bufnr != bufnr('%')
    return
  endif

  if s:complete_state.insert_before
    execute "normal! i" . a:text
    let s:complete_state.insert_before = 0
  else
    execute "normal! a" . a:text
  endif
  execute "undojoin"
  execute "redraw"
endfunction

function! s:OnCompleteDone()
  call s:SetNoPaste()
  echo 'Done.'
  execute "redraw"
endfunction

function! s:OnCompleteError(err)
  call s:SetNoPaste()
  echoerr 'AI Error: ' . a:err
  execute "redraw"
endfunction

" =============================================================================
" 聊天渲染状态
" =============================================================================

let s:chat_state = {'started': 0, 'bufnr': 0}

" =============================================================================
" AI 聊天命令
" =============================================================================

function! vim_ai#AIChatRun(uses_range, config, ...) dict range abort
  let l:config = vim_ai_config#ExtendDeep(g:vim_ai_chat, a:config)

  if a:uses_range
    let l:is_selection = g:vim_ai_is_selection_pending &&
          \ a:firstline == line("'<") && a:lastline == line("'>")
    let l:selection = s:GetSelectionOrRange(l:is_selection, a:firstline, a:lastline)
  else
    let l:is_selection = 0
    let l:selection = ''
  endif

  call s:SetPaste(get(g:vim_ai.chat.ui, 'paste_mode', 1))
  call s:ReuseOrCreateChatWindow()

  let l:instruction = ''
  let l:prompt = ''
  if a:0 > 0 || a:uses_range
    let l:instruction = a:0 > 0 ? a:1 : ''
    let l:prompt = s:MakePrompt(l:selection, l:instruction, l:config)
  endif

  let s:last_command = "chat"
  let s:last_config = a:config

  " 初始化聊天窗口
  call s:InitChatWindow(l:prompt)

  " 解析消息
  let l:full_content = trim(join(getline(1, '$'), "\n"))
  let [l:messages, l:header_opts] = s:ParseChatMessages(l:full_content)

  " 合并选项
  let l:api_opts = {
        \ 'model': g:vim_ai.api.model,
        \ 'endpoint_url': g:vim_ai.api.endpoint_url,
        \ 'temperature': g:vim_ai.api.temperature,
        \ 'top_p': get(g:vim_ai.api, 'top_p', 0.8),
        \ 'timeout': get(g:vim_ai.api, 'timeout', 30),
        \ }
  let l:api_opts = extend(l:api_opts, l:header_opts)

  " 检查是否有用户消息
  if len(l:messages) == 0 || l:messages[-1].role !=# 'user' || empty(l:messages[-1].content)
    call s:SetNoPaste()
    return
  endif

  " 准备 assistant 区域
  execute "normal! Go\n<<< assistant\n\n"
  execute "redraw"
  echo 'Answering...'

  " 聊天渲染状态
  let s:chat_state.started = 0
  let s:chat_state.bufnr = bufnr('%')

  " 发送请求
  let s:current_ctx_id = vim_ai_http#ChatStream(
        \ l:api_opts, l:messages,
        \ function('s:OnChatChunk'),
        \ function('s:OnChatDone'),
        \ function('s:OnChatError')
        \ )
endfunction

function! s:InitChatWindow(initial_prompt)
  let l:lines = getline(1, '$')
  let l:has_user = 0
  for l:line in l:lines
    if l:line ==# '>>> user'
      let l:has_user = 1
      break
    endif
  endfor

  if !l:has_user
    let l:init_prompt = get(g:vim_ai.chat, 'initial_prompt', [])
    if type(l:init_prompt) == type([])
      let l:init_text = join(l:init_prompt, "\n")
    else
      let l:init_text = l:init_prompt
    endif
    call append(0, split(l:init_text, "\n"))
    call append(line('$'), ['', '>>> user', ''])
    execute "normal! G"
  endif

  " 确保最后是 user
  let l:content = trim(join(getline(1, '$'), "\n"))
  let l:role_lines = []
  for l:line in split(l:content, "\n")
    if l:line =~# '^>>> user\|^>>> system\|^<<< assistant'
      call add(l:role_lines, l:line)
    endif
  endfor

  if len(l:role_lines) > 0 && l:role_lines[-1] !~# '^>>> user'
    execute "normal! Go\n>>> user\n\n"
  endif

  if !empty(a:initial_prompt)
    execute "normal! i" . a:initial_prompt
  endif

  execute "normal! G"
  execute "redraw"
endfunction

function! s:ParseChatMessages(content)
  let l:lines = split(a:content, "\n")
  let l:messages = []
  let l:chat_opts = {}
  let l:in_opts = 0

  for l:line in l:lines
    if l:line ==# '[chat-options]'
      let l:in_opts = 1
      continue
    endif
    if l:in_opts
      if empty(l:line)
        let l:in_opts = 0
        continue
      endif
      if l:line[0] ==# '#'
        continue
      endif
      let l:eq = stridx(l:line, '=')
      if l:eq > 0
        let l:key = trim(l:line[:l:eq - 1])
        let l:val = trim(l:line[l:eq + 1:])
        let l:chat_opts[l:key] = l:val
      endif
      continue
    endif

    if l:line ==# '>>> system'
      call add(l:messages, {'role': 'system', 'content': ''})
      continue
    endif
    if l:line ==# '>>> user'
      call add(l:messages, {'role': 'user', 'content': ''})
      continue
    endif
    if l:line ==# '>>> include'
      call add(l:messages, {'role': 'include', 'content': ''})
      continue
    endif
    if l:line ==# '<<< assistant'
      call add(l:messages, {'role': 'assistant', 'content': ''})
      continue
    endif
    if len(l:messages) > 0
      let l:messages[-1].content .= "\n" . l:line
    endif
  endfor

  " 处理 include
  let l:pwd = getcwd()
  let l:result = []
  for l:msg in l:messages
    let l:msg.content = trim(l:msg.content)
    if l:msg.role ==# 'include'
      let l:msg.role = 'user'
      let l:paths = split(l:msg.content, "\n")
      let l:msg.content = ''
      for l:p in l:paths
        let l:p = trim(l:p)
        if empty(l:p)
          continue
        endif
        let l:full = expand(l:p)
        if filereadable(l:full)
          try
            let l:content = readfile(l:full)
            let l:msg.content .= "\n\n==> " . l:full . " <==\n" . join(l:content, "\n")
          catch
          endtry
        endif
      endfor
    endif
    call add(l:result, l:msg)
  endfor

  return [l:result, l:chat_opts]
endfunction

function! s:OnChatChunk(text)
  if !a:text
    return
  endif
  if !s:chat_state.started && !trim(a:text)
    return
  endif
  if s:chat_state.bufnr != bufnr('%')
    return
  endif
  let s:chat_state.started = 1
  execute "normal! a" . a:text
  execute "undojoin"
  execute "redraw"
endfunction

function! s:OnChatDone()
  call s:SetNoPaste()
  execute "normal! a\n\n>>> user\n\n"
  execute "redraw"
  echo 'Done.'
endfunction

function! s:OnChatError(err)
  call s:SetNoPaste()
  echoerr 'AI Error: ' . a:err
  execute "redraw"
endfunction

" =============================================================================
" 新建聊天
" =============================================================================

function! vim_ai#AINewChatRun(...) abort
  let l:preset = a:0 > 0 ? a:1 : g:vim_ai.chat.window.preset
  call s:OpenChatWindow(l:preset)
  call vim_ai#AIChatRun(0, {})
endfunction

" =============================================================================
" 重做
" =============================================================================

function! vim_ai#AIRedoRun() abort
  undo
  if s:last_command ==# "complete"
    exe s:last_firstline . "," . s:last_lastline . "call vim_ai#AIRun(s:last_config, s:last_instruction, s:last_is_selection)"
  elseif s:last_command ==# "chat"
    call vim_ai#AIChatRun(0, s:last_config)
  endif
endfunction

" =============================================================================
" 补全函数
" =============================================================================

function! vim_ai#RoleCompletion(A,L,P) abort
  let l:roles = vim_ai_roles#GetNames()
  let l:result = []
  for l:r in l:roles
    let l:full = '/' . l:r
    if l:full =~# '^' . a:A
      call add(l:result, l:full)
    endif
  endfor
  return l:result
endfunction

function! vim_ai#WindowPresetCompletion(A,L,P) abort
  return filter(keys(g:vim_ai_open_chat_presets), 'v:val =~ "^' . a:A . '"')
endfunction

" =============================================================================
" 配置显示
" =============================================================================

function! vim_ai#ShowConfig() abort
  echo "Vim-AI Current Configuration:"
  echo "================================"
  echo "Provider:     " . g:vim_ai.api.provider
  echo "Model:        " . g:vim_ai.api.model
  echo "Endpoint:     " . g:vim_ai.api.endpoint_url
  echo "Temperature:  " . g:vim_ai.api.temperature
  echo "Chat Window:  " . g:vim_ai.chat.window.preset
  echo "Roles File:   " . g:vim_ai.roles.config_file
  echo "Debug:        " . (g:vim_ai.debug.enabled ? "ON" : "OFF")
endfunction
