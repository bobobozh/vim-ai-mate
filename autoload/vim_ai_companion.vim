" =============================================================================
" Vim-AI 陪伴编写模块
"
" 核心理念：不打断你的写作节奏
" — 不要求你停下来等：只要你一直在写，编辑量积累到阈值就会触发
" — 触发：编辑量累积（字符/改动事件）+ 冷却期 + 有真实输入
" — 频率：冷却期内最多一次（默认 5 分钟）
" — 风格：1-2 句、20-35 字、有具体依据、不矫情
"
" 用法:
"   :AICompanionOn                — 开启（冷却 5 分钟，编辑量阈值 60）
"   :AICompanionOn 10             — 冷却 10 分钟
"   :AICompanionOn 5 80           — 冷却 5 分钟，编辑量阈值 80
"   :AICompanionOff               — 关闭
"   :AICompanionStatus            — 查看状态（含已积累编辑量）
" =============================================================================

let s:enabled = 0
let s:cooldown_minutes = 5
let s:edit_threshold = 60        " 累计编辑量达到多少触发一次

let s:last_triggered = 0
let s:last_activity = 0
let s:edit_volume = 0            " 自上次触发以来累计的编辑量
let s:line_delta = 0             " 自上次触发以来净增/减行数
let s:last_changedtick = 0
let s:compose_state = 0          " 正在等待 AI 回复
let s:timer_id = -1

" =============================================================================
" 开关
" =============================================================================

function! vim_ai_companion#Enable(...) abort
  let s:enabled = 1

  if a:0 > 0
    let l:n = str2nr(a:1)
    if l:n > 0 && l:n < 120
      let s:cooldown_minutes = l:n
    endif
  endif
  if a:0 > 1
    let l:t = str2nr(a:2)
    if l:t >= 10 && l:t <= 2000
      let s:edit_threshold = l:t
    endif
  endif

  call s:SetupAutocmds()
  call s:StartTimer()
  call s:ResetTracking()

  echo printf('AI Companion 已开启（冷却 %d 分钟，编辑量阈值 %d，边写边判断）',
        \ s:cooldown_minutes, s:edit_threshold)
endfunction

function! vim_ai_companion#Disable() abort
  let s:enabled = 0
  augroup vim_ai_companion
    autocmd!
  augroup END
  call s:StopTimer()
  call s:ResetTracking()
  echo 'AI Companion 已关闭'
endfunction

function! vim_ai_companion#Status() abort
  if s:enabled == 0
    echo 'AI Companion: OFF（:AICompanionOn 开启）'
    return
  endif

  let l:elapsed = s:last_triggered > 0 ? localtime() - s:last_triggered : -1
  let l:remaining = s:last_triggered > 0
        \ ? max([0, s:cooldown_minutes * 60 - l:elapsed])
        \ : 0

  echo printf('AI Companion: ON | 冷却 %dm | 剩余 %ds | 编辑量 %d/%d | 净行变化 %+d | 等待回复 %s',
        \ s:cooldown_minutes,
        \ l:remaining,
        \ s:edit_volume,
        \ s:edit_threshold,
        \ s:line_delta,
        \ s:compose_state ? 'yes' : 'no')
endfunction

" =============================================================================
" 注册 / 重置
" =============================================================================

function! s:SetupAutocmds() abort
  augroup vim_ai_companion
    autocmd!
    autocmd TextChangedI * call s:Accumulate(1)
    autocmd TextChanged  * call s:Accumulate(2)
    autocmd BufEnter     * call s:OnBufEnter()
  augroup END
endfunction

function! s:StartTimer() abort
  call s:StopTimer()
  if !has('timers')
    return
  endif
  " 每 10 秒检查一次累计编辑量，不在输入路径上做任何重活
  let s:timer_id = timer_start(10000, function('s:OnTick'), {'repeat': -1})
endfunction

function! s:StopTimer() abort
  if s:timer_id != -1
    silent! call timer_stop(s:timer_id)
    let s:timer_id = -1
  endif
endfunction

function! s:ResetTracking() abort
  let s:last_triggered = 0
  let s:last_activity = 0
  let s:edit_volume = 0
  let s:line_delta = 0
  let s:baseline_lines = line('$')
  let s:last_changedtick = b:changedtick
  let s:compose_state = 0
endfunction

" =============================================================================
" 编辑量累计（只做轻量计数，不做任何 IO）
" =============================================================================

function! s:Accumulate(weight) abort
  if s:enabled == 0 || s:compose_state
    return
  endif

  " 跳过对话/结构树等非编辑 buffer
  if &buftype !=# '' || &readonly
    return
  endif
  if &filetype =~# '^\(aichat\|aistructure\|help\|fugitive\)$'
    return
  endif

  " 用 changedtick 差值估算这一轮改动规模
  let l:delta = max([1, b:changedtick - s:last_changedtick])
  let s:last_changedtick = b:changedtick

  let s:edit_volume += a:weight * min([l:delta, 10])
  let s:last_activity = localtime()

  " 净行变化：正数在展开写，负数在精简
  let s:line_delta = line('$') - s:baseline_lines
endfunction

function! vim_ai_companion#OnBufEnter() abort
  if s:enabled == 0
    return
  endif
  " 换文件：重新建立基线，避免跨文件累计误判
  let s:baseline_lines = line('$')
  let s:last_changedtick = b:changedtick
endfunction

" =============================================================================
" 定时检查 — 满足条件就异步触发，不阻塞任何编辑
" =============================================================================

function! s:OnTick(...) abort
  if s:enabled == 0 || s:compose_state
    return
  endif

  " 兜底：有些改动不触发 TextChanged/TextChangedI（脚本、插件写入等），
  " 用 changedtick 差值补齐，保证编辑量真实反映实际写作量
  call s:HarvestChangedtick()

  " 冷却期
  if s:last_triggered > 0 && localtime() - s:last_triggered < s:cooldown_minutes * 60
    return
  endif

  " 编辑量还没积累够
  if s:edit_volume < s:edit_threshold
    return
  endif

  " 最近仍在活动（避免离开一段时间回来时补发一条）
  if localtime() - s:last_activity > 120
    return
  endif

  call s:TryTrigger()
endfunction

function! s:HarvestChangedtick() abort
  if &buftype !=# '' || &readonly
    let s:last_changedtick = b:changedtick
    return
  endif

  let l:delta = b:changedtick - s:last_changedtick
  if l:delta > 0
    let s:edit_volume += min([l:delta, 40])
    let s:last_activity = localtime()
  endif
  let s:last_changedtick = b:changedtick
endfunction

" =============================================================================
" 触发前的场景过滤
" =============================================================================

function! s:TryTrigger() abort
  " 跳过不对的 buffer
  let l:skip_fts = ['aichat', 'aistructure', 'nofile', 'fugitive', 'NvimTree', 'tagbar', 'help']
  if index(l:skip_fts, &filetype) >= 0
    return
  endif
  if &buftype !=# '' || &readonly
    return
  endif
  if line('$') > 1500
    return
  endif
  if line('$') < 3 || empty(trim(join(getline(1, min([20, line('$')])), '')))
    return
  endif

  " 快照本次触发时的状态，用于 prompt
  let l:gap_minutes = s:last_triggered > 0
        \ ? (localtime() - s:last_triggered) / 60
        \ : -1
  let l:volume = s:edit_volume
  let l:line_delta = s:line_delta

  let s:compose_state = 1
  let s:last_triggered = localtime()

  " 重置累计
  let s:edit_volume = 0
  let s:line_delta = 0
  let s:baseline_lines = line('$')

  " 陪伴功能静默失败：API key 缺失、网络异常都不打断编码
  try
    call s:GenerateCompanion(l:volume, l:line_delta, l:gap_minutes)
  catch
    let s:compose_state = 0
  endtry
endfunction

" =============================================================================
" 构造 prompt 并异步调用 AI
" =============================================================================

function! s:GenerateCompanion(volume, line_delta, gap_minutes) abort
  let l:filename = expand('%:t')
  let l:ft = &filetype
  let l:line_count = line('$')
  let l:cursor_line = line('.')
  let l:col_name = expand('%:h:t')

  let l:recent_start = max([1, l:cursor_line - 12])
  let l:recent_end = min([l:line_count, l:cursor_line + 4])
  let l:recent_lines = getline(l:recent_start, l:recent_end)

  let l:git_branch = ''
  try
    let l:git_branch = substitute(system('git rev-parse --abbrev-ref HEAD 2>/dev/null'), '\n', '', '')
  catch
  endtry

  let l:hour = str2nr(strftime('%H'))
  let l:time_desc = l:hour >= 23 || l:hour < 6 ? '深夜' : (l:hour < 9 ? '清晨' : (l:hour < 12 ? '上午' : (l:hour < 18 ? '下午' : '晚上')))

  let l:writing_mode = l:line_delta > 5 ? '正在展开写新内容'
        \ : (l:line_delta < -5 ? '正在删减/精简' : '在原有结构上反复打磨')

  let l:gap_desc = a:gap_minutes < 0 ? '这是第一次开口' : ('距上次开口约 ' . a:gap_minutes . ' 分钟')
  let l:intensity = a:volume >= s:edit_threshold * 3 ? '高强度连续写作'
        \ : (a:volume >= s:edit_threshold * 2 ? '持续写了较长一段' : '刚写了一小段')

  let l:ctx = "文件: " . l:filename . " (" . (empty(l:ft) ? '无后缀' : l:ft) . ")\n"
        \ . "总行数: " . l:line_count . "  光标: 第 " . l:cursor_line . " 行\n"
        \ . (empty(l:col_name) ? '' : "项目: " . l:col_name . "\n")
        \ . (empty(l:git_branch) ? '' : "分支: " . l:git_branch . "\n")
        \ . "时段: " . l:time_desc . "\n"
        \ . "写作状态: " . l:writing_mode . "（净行变化 " . printf('%+d', a:line_delta) . "）\n"
        \ . "连续强度: " . l:intensity . "（累计编辑量 " . a:volume . "）\n"
        \ . "开口间隔: " . l:gap_desc . "\n"
        \ . "---\n光标附近内容:\n"
  for l:l in l:recent_lines
    let l:ctx .= "  " . l:l . "\n"
  endfor

  let l:prompt =
        \ "你是一个长期陪在身边的写作/编码伙伴。不是点评机器人，也不是啦啦队。\n"
        \ . "对方刚刚连续写了一段，现在是你开口的时机。\n\n"
        \ . "请从下面三种陪伴姿态中，只挑**最贴合此刻**的一种，说一句：\n"
        \ . "A 启发式：提一个小问题或换个视角，帮对方自己往下想。"
        \ . "（例：这段和上面的错误处理是不是有点重复？/ 这个函数再拆一层会不会更好读？）\n"
        \ . "B 反馈式：指出刚写内容里**具体的一处**，说明它好在哪里或值得再看一眼。"
        \ . "（例：这个边界条件兜得挺细 / 命名 swtich 之后这里能自解释）\n"
        \ . "C 提醒式：节奏、身体、上下文切换方面的简短提醒，要有依据。"
        \ . "（例：这段已经改了三轮，先跑一遍看看 / 坐了挺久，起来倒杯水）\n\n"
        \ . "硬性要求：\n"
        \ . "1. 只输出 1 句，20-35 字，最多 40 字；只选一种姿态，不要分点罗列\n"
        \ . "2. 必须落在上下文里的具体内容上，不能泛泛而谈；引用不了细节就选 C\n"
        \ . "3. 不说'加油''保持专注''继续努力''你可以的'，不说'朋友'，不用 emoji，不用感叹号\n"
        \ . "4. 不下结论、不评判对错，除非问题一目了然；不假装看到了没给出的代码\n"
        \ . "5. 语气平静、克制，可以有一点幽默；不煽情、不矫揉造作、不堆比喻\n"
        \ . "6. 如果内容还很碎、看不出意图，就说一句降低压力的话，别硬找问题\n"
        \ . "7. 深夜或高强度连续写作时，优先考虑 C（提醒式），但不要说教\n"
        \ . "8. 不要重复常见 IDE 提示语，也不要模仿客服语气\n\n"
        \ . "上下文：\n" . l:ctx . "\n"
        \ . "直接输出这句话本身，不要引号、不要前缀、不要解释你选了哪种姿态。"

  let l:api_opts = {
        \ 'model': vim_ai_config#Get('api.model', 'qwen-plus'),
        \ 'endpoint_url': vim_ai_config#Get('api.endpoint_url'),
        \ 'temperature': 0.7,
        \ 'timeout': vim_ai_config#Get('api.timeout', 20),
        \ }

  call vim_ai_http#ChatOnce(
        \ l:api_opts,
        \ [{'role': 'user', 'content': l:prompt}],
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

  " 清理可能的引号 / markdown 标记
  let l:text = substitute(l:text, '^\s*[>*"\x60]\s*', '', '')
  let l:text = substitute(l:text, '\s*[>*"\x60]\s*$', '', '')
  let l:text = substitute(l:text, '^"', '', '')
  let l:text = substitute(l:text, '"$', '', '')

  if strlen(l:text) < 5 || strlen(l:text) > 60
    return
  endif

  call s:Deliver(l:text)
endfunction

function! vim_ai_companion#OnError(err)
  let s:compose_state = 0
  " 静默失败：不打断编码
endfunction

" =============================================================================
" 输出：写入已打开的 AIChat 窗口 + 消息区
" =============================================================================

function! s:Deliver(text) abort
  let l:target_bufnr = -1
  if bufexists('>>> AI chat')
    let l:target_bufnr = bufnr('>>> AI chat')
  else
    for l:bid in getbufinfo()
      if getbufvar(l:bid.bufnr, '&filetype') ==# 'aichat'
        let l:target_bufnr = l:bid.bufnr
        break
      endif
    endfor
  endif

  if l:target_bufnr > 0
    call s:AppendToChat(l:target_bufnr, a:text)
  endif

  " echomsg 会留在 :messages 里，且不会打断输入
  echomsg '💭 ' . a:text
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

    let l:wins = win_findbuf(a:bufnr)
    if !empty(l:wins)
      let l:cur = win_getid()
      call win_gotoid(l:wins[0])
      normal! G
      call win_gotoid(l:cur)
    endif
  catch
  endtry
endfunction
