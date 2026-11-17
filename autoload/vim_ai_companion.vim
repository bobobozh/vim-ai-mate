" =============================================================================
" Vim-AI 陪伴编写模块
"
" 核心理念：在你编码时偶尔跳出来说句贴心的话
" — 根据当前文件、后缀、最近输入，异步调 AI 生成简短陪伴话语
" — 时机：光标空闲 + 满足触发条件（不是每次打字）
" — 频率：冷却期内只触发一次，避免打扰
" — 风格：简洁、不矫情、有实质感（不说"加油！"这种废话）
"
" 用法:
"   :AICompanionOn            — 开启（默认 5 分钟冷却）
"   :AICompanionOn 10         — 开启 + 设置 10 分钟冷却
"   :AICompanionOff           — 关闭
"   :AICompanionStatus        — 查看状态
" =============================================================================

let s:enabled = 0
let s:cooldown_minutes = 5
let s:last_triggered = 0
let s:last_input_time = 0
let s:idle_seconds = 8        " 光标空闲多少秒后开始检查
let s:activity_count = 0      " 当前 buffer 的累计活动（行数变化）
let s:current_buffer = ''
let s:compose_state = 0        " 正在等待 AI 回复

" =============================================================================
" 开关
" =============================================================================

function! vim_ai_companion#Enable(...) abort
  let s:enabled = 1
  if a:0 > 0
    let l:n = str2nr(a:1)
    if l:n > 0 && l:n < 60
      let s:cooldown_minutes = l:n
    endif
  endif
  call s:SetupAutocmds()
  call s:ResetTracking()
  echo 'AI Companion 已开启（冷却 ' . s:cooldown_minutes . ' 分钟，空闲 ' . s:idle_seconds . ' 秒触发）'
endfunction

function! vim_ai_companion#Disable() abort
  let s:enabled = 0
  augroup vim_ai_companion
    autocmd!
  augroup END
  call s:ResetTracking()
  echo 'AI Companion 已关闭'
endfunction

function! vim_ai_companion#Status() abort
  if s:enabled == 0
    echo 'AI Companion: OFF（:AICompanionOn 开启）'
    return
  endif
  let l:elapsed = localtime() - s:last_triggered
  let l:remaining = max([0, s:cooldown_minutes * 60 - l:elapsed])
  echo printf('AI Companion: ON | 冷却 %dm | 上次触发 %ds 前 | 剩余冷却 %ds | 等待回复: %s',
        \ s:cooldown_minutes, l:elapsed, l:remaining, s:compose_state ? 'yes' : 'no')
endfunction

" =============================================================================
" Autocmd 注册
" =============================================================================

function! s:SetupAutocmds() abort
  augroup vim_ai_companion
    autocmd!
    " 空闲触发检查
    execute 'autocmd CursorHoldI * call vim_ai_companion#OnIdle()'
    " 活动追踪（用户在输入时）
    execute 'autocmd TextChangedI * call vim_ai_companion#OnActivity()'
    " 换文件时重置
    execute 'autocmd BufEnter * call vim_ai_companion#OnBufEnter()'
  augroup END
endfunction

function! s:ResetTracking() abort
  let s:last_triggered = 0
  let s:last_input_time = 0
  let s:activity_count = 0
  let s:compose_state = 0
  let s:current_buffer = ''
endfunction

" =============================================================================
" 事件处理
" =============================================================================

function! vim_ai_companion#OnBufEnter() abort
  if s:enabled == 0 || s:compose_state
    return
  endif
  let s:current_buffer = expand('%:p')
  let s:activity_count = 0
  let s:last_input_time = localtime()
endfunction

function! vim_ai_companion#OnActivity() abort
  if s:enabled == 0
    return
  endif
  let s:last_input_time = localtime()
  let s:activity_count += 1
endfunction

function! vim_ai_companion#OnIdle() abort
  if s:enabled == 0 || s:compose_state
    return
  endif

  " 冷却检查
  if localtime() - s:last_triggered < s:cooldown_minutes * 60
    return
  endif

  " 空闲时间检查
  if localtime() - s:last_input_time < s:idle_seconds
    return
  endif

  call s:TryTrigger()
endfunction

" =============================================================================
" 触发逻辑 — 综合判断当前是否值得说句贴心话
" =============================================================================

function! s:TryTrigger() abort
  let l:bufnr = bufnr('%')

  " 跳过的 buffer 类型
  let l:skip_fts = ['aichat', 'aistructure', 'nofile', 'fugitive', 'NvimTree', 'tagbar']
  let l:ft = &filetype
  if index(l:skip_fts, l:ft) >= 0
    return
  endif
  if &buftype =~# 'prompt' || &readonly
    return
  endif

  " 跳过 aichat 之外的 scratch buffer
  if &buftype !=# ''
    return
  endif

  " 活动量检查 — 不是完全没动过
  if s:activity_count < 2
    return
  endif

  " 大文件跳过（避免 AI 上下文太大）
  if line('$') > 1500
    return
  endif

  " 连续触发保护
  if s:compose_state
    return
  endif

  let s:compose_state = 1
  let s:last_triggered = localtime()

  call s:GenerateCompanion()
endfunction

" =============================================================================
" 构造 prompt 并异步调用 AI
" =============================================================================

function! s:GenerateCompanion() abort
  let l:filename = expand('%:t')
  let l:filepath = expand('%:p')
  let l:ft = &filetype
  let l:line_count = line('$')
  let l:cursor_line = line('.')
  let l:cursor_col = col('.')
  let l:col_name = expand('%:h:t')

  " 收集最近几行输入（光标附近）
  let l:recent_start = max([1, l:cursor_line - 15])
  let l:recent_end = min([l:line_count, l:cursor_line + 5])
  let l:recent_lines = getline(l:recent_start, l:recent_end)

  " 当前行的文本
  let l:current_line = getline('.')

  " Git 上下文（可选）
  let l:git_branch = ''
  try
    let l:git_branch = substitute(system('git rev-parse --abbrev-ref HEAD 2>/dev/null'), '\n', '', '')
  catch
  endtry

  " 构造上下文
  let l:ctx = ''
  let l:ctx .= "文件: " . l:filename . "\n"
  let l:ctx .= "类型: " . l:ft . "  行数: " . l:line_count . "\n"
  if !empty(l:col_name)
    let l:ctx .= "项目目录: " . l:col_name . "\n"
  endif
  if !empty(l:git_branch)
    let l:ctx .= "分支: " . l:git_branch . "\n"
  endif
  let l:ctx .= "光标: 第 " . l:cursor_line . " 行, 第 " . l:cursor_col . " 列\n"
  let l:ctx .= "当前行: " . l:current_line . "\n"
  let l:ctx .= "---\n"
  let l:ctx .= "光标附近代码（-15~+5 行）:\n"
  for l:l in l:recent_lines
    let l:ctx .= "  " . l:l . "\n"
  endfor

  let l:prompt = "你是一个安静的编码伙伴。在程序员工作时，你偶尔（几分钟一次）跳出来说一句贴心的短句。\n\n" .
        "要求：\n" .
        "1. 1-2 句，20-35 字，非常短，不要超过 40 字\n" .
        "2. 根据当前文件类型、内容、光标位置，说点**有具体依据的**话\n" .
        "3. 不说空泛的'加油'、'保持专注'这种话\n" .
        "4. 语气：平静、关照、偶尔带点幽默感，不要亢奋\n" .
        "5. 如果看起来是在调试报错，可以说'报错有点棘手？换个角度看看'\n" .
        "6. 如果看起来一直在写测试，可以说'测试写得挺扎实'\n" .
        "7. 如果光标停在空行或注释里，可以说'在想什么？'\n" .
        "8. 如果是深夜（23:00-06:00），偶尔可以温和提醒节奏\n" .
        "9. 不要用 emoji，不要用感叹号，不要说'朋友'\n\n" .
        "当前上下文：\n" . l:ctx . "\n\n" .
        "现在，请说一句。直接输出这句话本身，不要前缀后缀。"

  let l:api_opts = {
        \ 'model': vim_ai_config#Get('api.model', 'qwen-plus'),
        \ 'endpoint_url': vim_ai_config#Get('api.endpoint_url'),
        \ 'temperature': 0.6,
        \ 'timeout': vim_ai_config#Get('api.timeout', 15),
        \ }

  let l:messages = [
        \ {'role': 'user', 'content': l:prompt},
        \ ]

  call vim_ai_http#ChatOnce(
        \ l:api_opts, l:messages,
        \ function('vim_ai_companion#OnDone'),
        \ function('vim_ai_companion#OnError')
        \ )
endfunction

" =============================================================================
" 回调
" =============================================================================

function! vim_ai_companion#OnDone(result)
  let s:compose_state = 0

  let l:text = trim(a:result.content)

  " 清理一下可能的 markdown/prefix
  let l:text = substitute(l:text, '^\s*[>*"\x60]\s*', '', '')
  let l:text = substitute(l:text, '\s*[>*"\x60]\s*$', '', '')
  let l:text = substitute(l:text, '^"', '', '')
  let l:text = substitute(l:text, '"$', '', '')

  " 太短或太长都跳过
  if strlen(l:text) < 5 || strlen(l:text) > 60
    return
  endif

  " 分发输出
  call s:Deliver(l:text)
endfunction

function! vim_ai_companion#OnError(err)
  let s:compose_state = 0
  " 静默失败，不打扰
endfunction

" =============================================================================
" 输出分发
" 如果有打开的 AIChat 窗口，写到里面；否则 echo
" =============================================================================

function! s:Deliver(text) abort
  let l:target_bufnr = -1
  let l:chat_win_ids = win_findbuf(bufnr('>>> AI chat'))
  if !empty(l:chat_win_ids)
    let l:target_bufnr = bufnr('>>> AI chat')
  else
    " 尝试通过 filetype 找 aichat buffer
    for l:tab in range(tabpagenr('$'))
      call extend(l:chat_win_ids, win_findbuf(filter(tabpagebuflist(l:tab + 1), 'getbufvar(v:val, "&filetype") ==# "aichat"')))
    endfor
    if !empty(l:chat_win_ids)
      let l:target_bufnr = tabpagebuflist(tabpagenr())[l:chat_win_ids[0] - 1]
    endif
  endif

  if l:target_bufnr > 0
    " 追加到对话窗口
    call s:AppendToChat(l:target_bufnr, a:text)
  endif

  " 同时在 command line 显示
  echo '💭 ' . a:text
endfunction

function! s:AppendToChat(bufnr, text) abort
  try
    let l:lines = getbufline(a:bufnr, 1, '$')
    call add(l:lines, '')
    call add(l:lines, '>>> companion')
    call add(l:lines, '')
    call add(l:lines, a:text)
    call add(l:lines, '')
    call setbufline(a:bufnr, 1, l:lines)

    " 尝试滚到底部
    let l:wins = win_findbuf(a:bufnr)
    if !empty(l:wins)
      execute l:wins[0] . 'wincmd w'
      execute 'normal! G'
      wincmd p
    endif
  catch
  endtry
endfunction
