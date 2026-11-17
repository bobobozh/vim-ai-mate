" =============================================================================
" Vim-AI 英语写作辅助模块
"
" 功能:
"   :AECheck   — 实时检查 buffer 中的英语，标注问题
"   :AEWrite   — 写作练习模式，AI 多维度反馈 + side-by-side 对比
"   :AESave    — 把选中的好表达存到表达库
"   :AESearch  — 模糊检索表达库
"   :AEPaste   — 把库中表达插入当前 buffer
"   :AESay     — 调用系统 TTS 朗读
"   :AEPhonetic — 生成音标和发音要点
"
" 设计理念：和日常英语训练习惯对齐（广播、歌曲、背诵、发音）
" =============================================================================

let s:check_buffer = ''
let s:check_matches = []   " [{line, col_start, col_end, severity, message}]
let s:write_state = {}

" =============================================================================
" 命令注册
" =============================================================================

command! -range -nargs=? AECheck     <line1>,<line2>call vim_ai_english#Check(<count>, <q-args>)
command! AECheckClear                 call vim_ai_english#CheckClear()
command! -nargs=? AEWrite             call vim_ai_english#WriteStart(<q-args>)
command! -nargs=? AESay               call vim_ai_english#Say(<q-args>)
command! -range AEPhonetic            <line1>,<line2>call vim_ai_english#Phonetic()
command! -range AESave                <line1>,<line2>call vim_ai_english#SaveExpression()
command! -nargs=? AESearch            call vim_ai_english#SearchExpression(<q-args>)
command! AEPaste                      call vim_ai_english#PasteExpression()

" =============================================================================
" :AECheck — 检查英语文本（异步）
" 在 buffer 上用 :match 高亮标记问题行
" =============================================================================

function! vim_ai_english#Check(uses_range, ...) dict range abort
  let l:instruction = a:0 > 0 ? a:1 : ''

  if a:uses_range
    let l:is_selection = g:vim_ai_is_selection_pending &&
          \ a:firstline == line("'<") && a:lastline == line("'>")
    let l:text = s:GetSelectionOrRange(a:firstline, a:lastline, l:is_selection)
    let l:start_line = a:firstline
  else
    let l:text = join(getline(1, '$'), "\n")
    let l:start_line = 1
  endif

  if empty(l:text)
    echo '没有可检查的文本'
    return
  endif

  let s:check_start_line = l:start_line

  let l:prompt = "You are an English writing coach. Analyze the following English text.\n" .
        \ "Check for: grammar errors, spelling mistakes, unnatural phrasing, and awkward sentences.\n" .
        \ "Respond ONLY with a JSON array, where each item is:\n" .
        \ '[line_number, "severity: error|warning|suggestion", "issue description", "correction"]\n\n' .
        \ "Use relative line numbers starting from 1 for the provided text.\n\n" .
        \ "Text to analyze:\n```\n" . l:text . "\n```\n\n" .
        \ "If there are no issues, respond with: []"

  let l:api_opts = {
        \ 'model': vim_ai_config#Get('edit.model', 'qwen-turbo'),
        \ 'endpoint_url': vim_ai_config#Get('edit.endpoint_url', vim_ai_config#Get('api.endpoint_url')),
        \ 'temperature': 0.1,
        \ 'timeout': vim_ai_config#Get('api.timeout', 30),
        \ }

  let l:messages = [
        \ {'role': 'system', 'content': 'You are a strict English writing coach. Output ONLY JSON arrays. No markdown, no explanations.'},
        \ {'role': 'user', 'content': l:prompt},
        \ ]

  echo 'Checking English...'
  let l:ctx_id = vim_ai_http#ChatOnce(
        \ l:api_opts, l:messages,
        \ function('vim_ai_english#OnCheckDone'),
        \ function('vim_ai_english#OnCheckError')
        \ )
endfunction

function! vim_ai_english#OnCheckDone(result)
  let l:raw = trim(a:result.content)
  let l:usage = a:result.usage

  " 尝试从 AI 输出中提取 JSON
  let l:json = l:raw
  let l:start = stridx(l:raw, '[')
  let l:end = stridx(l:raw, ']', l:start)
  if l:start >= 0 && l:end > l:start
    let l:json = l:raw[l:start : l:end + 1]
  endif

  try
    let l:issues = json_decode(l:json)
  catch
    echoerr 'Failed to parse check result: ' . v:exception
    return
  endtry

  call s:ApplyCheckHighlights(l:issues)

  echo 'English check done: ' . len(l:issues) . ' issue(s) found.' . vim_ai#FormatUsage(l:usage)
endfunction

function! vim_ai_english#OnCheckError(err)
  echoerr 'English check failed: ' . a:err
endfunction

function! s:ApplyCheckHighlights(issues) abort
  " 先清掉旧的高亮
  call vim_ai_english#CheckClear()

  let s:check_buffer = bufnr('%')
  let s:check_matches = []

  let l:bufnr = bufnr('%')
  let l:start = s:check_start_line

  for l:issue in a:issues
    if type(l:issue) != type([]) || len(l:issue) < 4
      continue
    endif
    let l:rel_line = get(l:issue, 0, 0)
    let l:severity = get(l:issue, 1, 'suggestion')
    let l:desc = get(l:issue, 2, '')
    let l:correction = get(l:issue, 3, '')

    let l:abs_line = l:start + l:rel_line - 1

    " 根据严重程度用不同颜色高亮行
    let l:group = 'AICheckSuggestion'
    let l:pat = l:abs_line . '._'
    if l:severity =~# 'error'
      let l:group = 'AICheckError'
    elseif l:severity =~# 'warning'
      let l:group = 'AICheckWarning'
    endif

    call matchadd(l:group, l:pat)
    call add(s:check_matches, {
          \ 'line': l:abs_line,
          \ 'severity': l:severity,
          \ 'desc': l:desc,
          \ 'correction': l:correction,
          \ })
  endfor

  " 定义高亮组（如果还没定义）
  highlight default link AICheckError ErrorMsg
  highlight default link AICheckWarning WarningMsg
  highlight default link AICheckSuggestion Comment

  " 设置快速访问映射（光标在高亮行时按 enter 看详情）
  nnoremap <buffer> <silent> <leader>ce :call vim_ai_english#ShowUnderCursor()<CR>
endfunction

function! vim_ai_english#CheckClear() abort
  call clearmatches()
  try
    call matchdelete('AICheckError', -1)
    call matchdelete('AICheckWarning', -1)
    call matchdelete('AICheckSuggestion', -1)
  catch
  endtry
  unlet s:check_buffer
  let s:check_matches = []
endfunction

function! vim_ai_english#ShowUnderCursor() abort
  let l:line = line('.')
  for l:m in s:check_matches
    if l:m.line == l:line
      echo '[' . l:m.severity . '] ' . l:m.desc . ' → ' . l:m.correction
      return
    endif
  endfor
  echo 'No issue on this line.'
endfunction

" =============================================================================
" :AEWrite — 写作练习模式（side-by-side 对比原文和 AI 改写）
" =============================================================================

function! vim_ai_english#WriteStart(...) abort
  let l:prompt = a:0 > 0 ? a:1 : ''

  call s:OpenWriteSidebar()

  let l:text = join(getline(1, '$'), "\n")
  if empty(l:text)
    echo '当前 buffer 没有内容'
    return
  endif

  let s:write_state.original = l:text
  let s:write_state.bufnr = bufnr('%')

  " 构建多维度 feedback 提示词
  let l:instruction = "你是一位英语写作教练。请对以下英文文本从多个维度进行评估和改写。\n\n" .
        "请按以下格式输出：\n\n" .
        "【总体评分】X/10\n" .
        "【语法准确性】(简要评价)\n" .
        "【用词地道性】(简要评价)\n" .
        "【句式丰富度】(简要评价)\n" .
        "【风格连贯性】(简要评价)\n\n" .
        "【改写版本】\n" .
        "(给出你的完整改写版本，直接替换原文)\n\n" .
        "【逐句讲解】\n" .
        "(列出原文中每一处修改及其原因)\n"

  if !empty(l:prompt)
    let l:instruction .= "\n额外要求：" . l:prompt . "\n"
  endif

  let l:instruction .= "\n---\n需要评估的文本：\n" . l:text

  let l:api_opts = {
        \ 'model': vim_ai_config#Get('api.model', 'qwen-plus'),
        \ 'endpoint_url': vim_ai_config#Get('api.endpoint_url'),
        \ 'temperature': 0.3,
        \ 'timeout': vim_ai_config#Get('api.timeout', 30),
        \ }

  let l:messages = [
        \ {'role': 'system', 'content': 'You are a professional English writing coach.'},
        \ {'role': 'user', 'content': l:instruction},
        \ ]

  echo 'Writing analysis in progress...'
  call vim_ai_http#ChatStream(
        \ l:api_opts, l:messages,
        \ function('vim_ai_english#OnWriteChunk'),
        \ function('vim_ai_english#OnWriteDone'),
        \ function('vim_ai_english#OnWriteError')
        \ )
endfunction

let s:write_output = ''
let s:write_sidebar_bufnr = -1

function! s:OpenWriteSidebar() abort
  " 关掉已有的
  if s:write_sidebar_bufnr >= 0 && bufexists(s:write_sidebar_bufnr)
    try
      call execute('bwipeout ' . s:write_sidebar_bufnr)
    catch
    endtry
  endif

  rightbelow 50vnew
  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal filetype=markdown
  setlocal nowrap

  silent! file '>>> AI writing feedback'
  let s:write_sidebar_bufnr = bufnr('%')

  " 回到原窗口
  wincmd p
endfunction

function! vim_ai_english#OnWriteChunk(text)
  let s:write_output .= a:text
  if s:write_sidebar_bufnr >= 0 && bufexists(s:write_sidebar_bufnr)
    call setbufline(s:write_sidebar_bufnr, 1, split(s:write_output, "\n"))
    call execute('normal! G')
    call redraw()
  endif
endfunction

function! vim_ai_english#OnWriteDone(result)
  let l:usage = a:result.usage
  echo 'Writing analysis done.' . vim_ai#FormatUsage(l:usage)

  " 尝试提取改写版本供用户一键替换
  let l:rewrite = s:ExtractRewrite(s:write_output)
  if !empty(l:rewrite)
    echo ''
    echo '检测到改写版本。'
    echo '输入 y 用改写替换原文，输入 n 保持不变：'
    let l:choice = input('> ')
    if l:choice =~# '^y'
      let l:orig_bufnr = s:write_state.bufnr
      if bufnr('%') != l:orig_bufnr
        execute 'buffer ' . l:orig_bufnr
      endif
      execute 'normal! ggdG'
      call setline(1, split(l:rewrite, "\n"))
      echo '已替换。'
    endif
  endif

  let s:write_output = ''
endfunction

function! vim_ai_english#OnWriteError(err)
  echoerr 'Writing analysis failed: ' . a:err
  let s:write_output = ''
endfunction

function! s:ExtractRewrite(text) abort
  let l:start = stridx(a:text, '【改写版本】')
  if l:start < 0
    let l:start = stridx(a:text, '改写版本')
  endif
  if l:start < 0
    return ''
  endif
  let l:after = a:text[l:start:]
  let l:next_marker = matchstr(l:after[10:], '【\(逐句\|讲解\|说明\)')
  if empty(l:next_marker)
    return ''
  endif
  let l:end = stridx(l:after[10:], l:next_marker)
  let l:rewrite = l:after[10 : l:end - 1]
  return trim(l:rewrite)
endfunction

" =============================================================================
" :AESay — 调用系统 TTS 朗读
" =============================================================================

function! vim_ai_english#Say(...) abort
  let l:text = a:0 > 0 ? a:1 : ''

  if empty(l:text)
    " 没参数就读光标下的词
    let l:text = expand('<cword>')
  endif

  if empty(l:text)
    echo '没有可读内容'
    return
  endif

  let l:voice = get(g:vim_ai, 'english_say_voice', 'Samantha')

  " 异步执行 say（不阻塞 Vim）
  call job_start(['say', '-v', l:voice, l:text])
  echo '🔊 Saying: ' . l:text
endfunction

" =============================================================================
" :AEPhonetic — 音标和发音要点（异步）
" =============================================================================

function! vim_ai_english#Phonetic() dict range abort
  let l:word = s:GetSelectionOrRange(a:firstline, a:lastline, g:vim_ai_is_selection_pending)
  if empty(l:word)
    let l:word = expand('<cword>')
  endif
  if empty(l:word)
    echo '没有可查询的词'
    return
  endif

  let l:prompt = "For the English word/phrase: \"" . l:word . "\"\n\n" .
        "Provide:\n" .
        "1. IPA phonetic transcription\n" .
        "2. Part of speech\n" .
        "3. Brief pronunciation tips (stress, silent letters, etc.)\n" .
        "4. Common mispronunciations to avoid\n" .
        "5. Example sentences showing correct context\n"

  let l:api_opts = {
        \ 'model': vim_ai_config#Get('api.model', 'qwen-plus'),
        \ 'endpoint_url': vim_ai_config#Get('api.endpoint_url'),
        \ 'temperature': 0.3,
        \ 'timeout': vim_ai_config#Get('api.timeout', 30),
        \ }

  let l:messages = [
        \ {'role': 'user', 'content': l:prompt},
        \ ]

  echo 'Fetching phonetics for ' . l:word . '...'
  call vim_ai_http#ChatOnce(
        \ l:api_opts, l:messages,
        \ function('vim_ai_english#OnPhoneticDone'),
        \ function('vim_ai_english#OnPhoneticError')
        \ )
endfunction

function! vim_ai_english#OnPhoneticDone(result)
  let l:usage = a:result.usage
  echo ''
  echo '=== Phonetics ==='
  echo a:result.content
  echo vim_ai#FormatUsage(l:usage)
endfunction

function! vim_ai_english#OnPhoneticError(err)
  echoerr 'Phonetic lookup failed: ' . a:err
endfunction

" =============================================================================
" 表达积累库 — AESave / AESearch / AEPaste
" 存到 ~/.vim/ai_store/expressions/expressions.json
" =============================================================================

function! vim_ai_english#SaveExpression() dict range abort
  let l:selection = s:GetSelectionOrRange(a:firstline, a:lastline, g:vim_ai_is_selection_pending)
  if empty(l:selection)
    echo '没有选中内容'
    return
  endif

  let l:note = input('备注（可选）：')
  let l:tags = input('标签（逗号分隔）：')

  let l:entry = {
        \ 'text': l:selection,
        \ 'note': l:note,
        \ 'tags': split(l:tags, ',\\s*'),
        \ 'source_file': expand('%'),
        \ 'saved_at': strftime('%Y-%m-%d %H:%M:%S'),
        \ }

  let l:store_path = vim_ai_store#Path('expressions') . '/expressions.json'
  let l:all = []
  if filereadable(l:store_path)
    try
      let l:all = json_decode(join(readfile(l:store_path), "\n"))
    catch
      let l:all = []
    endtry
  endif

  call add(l:all, l:entry)
  call writefile([json_encode(l:all)], l:store_path)

  echo '已保存表达（共 ' . len(l:all) . ' 条）'
endfunction

function! vim_ai_english#SearchExpression(...) abort
  let l:query = a:0 > 0 ? a:1 : ''

  let l:store_path = vim_ai_store#Path('expressions') . '/expressions.json'
  if !filereadable(l:store_path)
    echo '表达库为空'
    return
  endif

  let l:all = json_decode(join(readfile(l:store_path), "\n"))
  let l:results = []

  for l:e in l:all
    if empty(l:query) ||
          \ matchstr(get(l:e, 'text', ''), l:query) ||
          \ matchstr(get(l:e, 'note', ''), l:query) ||
          \ match(join(get(l:e, 'tags', []), ' '), l:query) >= 0
      call add(l:results, l:e)
    endif
  endfor

  if empty(l:results)
    echo '没有找到匹配的表达'
    return
  endif

  echo ''
  echo '=== 表达库（' . len(l:results) . ' 条）=== '
  for l:i in range(len(l:results))
    let l:e = l:results[l:i]
    let l:preview = substitute(get(l:e.text, ''), '\n', ' ⏎ ', 'g')
    echo (l:i + 1) . '. ' . l:preview[:80]
    if !empty(get(l:e, 'note', ''))
      echo '   备注: ' . l:e.note
    endif
  endfor

  let l:choice = input('选择要插入的编号（回车取消）：')
  if !empty(l:choice) && str2nr(l:choice) > 0 && str2nr(l:choice) <= len(l:results)
    let l:selected = l:results[str2nr(l:choice) - 1]
    call setline(line('.'), split(l:selected.text, "\n"))
    echo '已插入。'
  endif
endfunction

function! vim_ai_english#PasteExpression() abort
  call vim_ai_english#SearchExpression('')
endfunction

" =============================================================================
" :AETutor — 英语教学讲解（流式侧边栏）
" 对选中的英语文本做逐句分析、地道表达建议、语言点讲解
" =============================================================================

let s:tutor_output = ''
let s:tutor_sidebar_bufnr = -1
let s:tutor_source_bufnr = -1

function! vim_ai_english#Tutor() dict range abort
  let l:is_selection = g:vim_ai_is_selection_pending &&
        \ a:firstline == line("'<") && a:lastline == line("'>")
  let l:text = s:GetSelectionOrRange(a:firstline, a:lastline, l:is_selection)
  if empty(l:text)
    echo '没有选中内容，Tutor 需要选中文本'
    return
  endif

  let s:tutor_source_bufnr = bufnr('%')
  let s:tutor_output = ''

  call s:OpenTutorSidebar()

  let l:prompt = "你是一位专业的英语老师，请对以下英文做逐句教学讲解。\n\n" .
        "讲解结构（每句都要覆盖）：\n" .
        "【原句】完整展示\n" .
        "【句意】中文直译 + 地道中文意译（如果直译不自然）\n" .
        "【语言点】本句的语法、固定搭配、词汇用法、语气\n" .
        "【更地道】如果有，给出更自然的改写；如果原句已经很好，写 '✓ 表达到位'\n" .
        "【扩展】相关同义词、短语、常见错误\n\n" .
        "要求：简洁、精准、实用；不要堆术语；重点突出真正有价值的讲解。\n\n" .
        "待讲解文本：\n" . l:text

  let l:api_opts = {
        \ 'model': vim_ai_config#Get('api.model', 'qwen-plus'),
        \ 'endpoint_url': vim_ai_config#Get('api.endpoint_url'),
        \ 'temperature': 0.3,
        \ 'timeout': vim_ai_config#Get('api.timeout', 60),
        \ }

  let l:messages = [
        \ {'role': 'user', 'content': l:prompt},
        \ ]

  echo 'English Tutor analyzing...'
  let l:ctx_id = vim_ai_http#ChatStream(
        \ l:api_opts, l:messages,
        \ function('vim_ai_english#OnTutorChunk'),
        \ function('vim_ai_english#OnTutorDone'),
        \ function('vim_ai_english#OnTutorError')
        \ )
endfunction

function! s:OpenTutorSidebar() abort
  if s:tutor_sidebar_bufnr >= 0 && bufexists(s:tutor_sidebar_bufnr)
    try
      call execute('bwipeout ' . s:tutor_sidebar_bufnr)
    catch
    endtry
  endif

  rightbelow 50vnew
  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal filetype=markdown
  setlocal nowrap

  silent! file '>>> English Tutor'
  let s:tutor_sidebar_bufnr = bufnr('%')

  wincmd p
endfunction

function! vim_ai_english#OnTutorChunk(text)
  let s:tutor_output .= a:text
  if s:tutor_sidebar_bufnr >= 0 && bufexists(s:tutor_sidebar_bufnr)
    call setbufline(s:tutor_sidebar_bufnr, 1, split(s:tutor_output, "\n"))
    call redraw()
  endif
endfunction

function! vim_ai_english#OnTutorDone(result)
  let l:usage = a:result.usage
  echo 'English Tutor done.' . vim_ai#FormatUsage(l:usage)
  let s:tutor_output = ''
endfunction

function! vim_ai_english#OnTutorError(err)
  echoerr 'English Tutor failed: ' . a:err
  let s:tutor_output = ''
endfunction

" =============================================================================
" 辅助
" =============================================================================

function! s:GetSelectionOrRange(first, last, is_selection) abort
  if a:is_selection
    let [lstart, cstart] = getpos("'<")[1:2]
    let [lend, cend] = getpos("'>")[1:2]
    let lines = getline(lstart, lend)
    if len(lines) > 0
      let lines[-1] = lines[-1][: cend - (&selection == 'inclusive' ? 1 : 2)]
      let lines[0] = lines[0][cstart - 1:]
    endif
    return join(lines, "\n")
  endif
  return join(getline(a:first, a:last), "\n")
endfunction
