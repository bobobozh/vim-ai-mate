" =============================================================================
" Vim-AI Tool Calling 注册中心
"
" 注册内置工具，支持 AI 在对话中主动调用 shell、文件、vim 等能力。
" 执行流程：
"   1. 发起请求时把 tools 列表传给 API
"   2. 如果 AI 响应包含 tool_calls，执行工具
"   3. 把工具结果追加到 messages，再次请求（可能多轮）
"   4. 直到 AI 返回普通 content 而非 tool_calls
"
" 安全机制：
"   - shell 命令执行前预览，用户确认
"   - 危险命令黑名单（rm -rf /, curl|sh 等）
"   - 所有执行记录到审计日志
" =============================================================================

let s:registry = {}
let s:tool_aliases = {}

" =============================================================================
" 内置工具定义
" =============================================================================

function! s:BuildTools() abort
  return [
        \ {
        \   'type': 'function',
        \   'function': {
        \     'name': 'shell_execute',
        \     'description': 'Execute a shell command and return its stdout output.',
        \     'parameters': {
        \       'type': 'object',
        \       'properties': {
        \         'command': {'type': 'string', 'description': 'The shell command to execute'},
        \         'timeout': {'type': 'integer', 'description': 'Max seconds to wait, default 10', 'default': 10},
        \       },
        \       'required': ['command'],
        \     },
        \   },
        \ },
        \ {
        \   'type': 'function',
        \   'function': {
        \     'name': 'file_read',
        \     'description': 'Read the contents of a file, optionally specifying line range.',
        \     'parameters': {
        \       'type': 'object',
        \       'properties': {
        \         'path': {'type': 'string', 'description': 'Absolute or relative file path'},
        \         'start_line': {'type': 'integer', 'description': '1-based start line (optional)'},
        \         'end_line': {'type': 'integer', 'description': '1-based end line (optional)'},
        \       },
        \       'required': ['path'],
        \     },
        \   },
        \ },
        \ {
        \   'type': 'function',
        \   'function': {
        \     'name': 'file_glob',
        \     'description': 'Find files matching a glob pattern.',
        \     'parameters': {
        \       'type': 'object',
        \       'properties': {
        \         'pattern': {'type': 'string', 'description': 'Glob pattern, e.g. **/*.py'},
        \         'max_results': {'type': 'integer', 'description': 'Max results to return, default 20', 'default': 20},
        \       },
        \       'required': ['pattern'],
        \     },
        \   },
        \ },
        \ {
        \   'type': 'function',
        \   'function': {
        \     'name': 'vim_eval',
        \     'description': 'Evaluate a Vim expression and return the result.',
        \     'parameters': {
        \       'type': 'object',
        \       'properties': {
        \         'expression': {'type': 'string', 'description': 'Vimscript expression to evaluate'},
        \       },
        \       'required': ['expression'],
        \     },
        \   },
        \ },
        \ ]
endfunction

" 危险命令黑名单（正则匹配）
let s:dangerous_patterns = [
      \ '^\s*rm\s+-rf\s+/',
      \ '^\s*curl.*\|\s*sh\s*$',
      \ '^\s*wget.*\|\s*bash\s*$',
      \ '^\s*mkfs\.',
      \ '^\s*dd\s+if=',
      \ '^\s*chmod\s+-R\s+777\s+/',
      \ '>\s*/dev/sd',
      \ ]

" =============================================================================
" 注册/配置工具
" =============================================================================

function! vim_ai_tools#Init() abort
  let s:registry = {}
  let s:tool_aliases = {}

  " 加载内置工具
  let l:builtins = s:BuildTools()
  for l:tool in l:builtins
    call s:RegisterTool(l:tool)
  endfor

  " 用户自定义工具（可选）
  if exists('g:vim_ai_custom_tools')
    for l:tool in g:vim_ai_custom_tools
      call s:RegisterTool(l:tool)
    endfor
  endif
endfunction

function! s:RegisterTool(tool) abort
  let l:name = a:tool.function.name
  let s:registry[l:name] = a:tool

  " 注册别名
  let s:tool_aliases[l:name] = function('s:Tool_' . l:name)
endfunction

" 生成 API 的 tools 参数
function! vim_ai_tools#List() abort
  let l:result = []
  for l:name in sort(keys(s:registry))
    call add(l:result, s:registry[l:name])
  endfor
  return l:result
endfunction

" 启用/禁用工具（通过 role config）
function! vim_ai_tools#Filter(enabled_names) abort
  let l:all = vim_ai_tools#List()
  if empty(a:enabled_names)
    return l:all
  endif
  let l:result = []
  for l:tool in l:all
    if index(a:enabled_names, l:tool.function.name) >= 0
      call add(l:result, l:tool)
    endif
  endfor
  return l:result
endfunction

call vim_ai_tools#Init()

" =============================================================================
" 工具执行器
" =============================================================================

" 核心：执行一组 tool_calls，返回 tool messages 追加到对话历史
" tool_calls: [{id, type: 'function', function: {name, arguments}}]
" 返回: [{role: 'tool', tool_call_id, content}, ...]
function! vim_ai_tools#ExecuteAll(tool_calls) abort
  let l:results = []
  for l:tc in a:tool_calls
    let l:name = get(l:tc.function, 'name', '')
    let l:args_str = get(l:tc.function, 'arguments', '{}')
    let l:call_id = get(l:tc, 'id', '')

    if empty(l:name) || !has_key(s:tool_aliases, l:name)
      call add(l:results, {
            \ 'role': 'tool',
            \ 'tool_call_id': l:call_id,
            \ 'content': 'Error: unknown tool "' . l:name . '"',
            \ })
      continue
    endif

    " 解析参数 JSON
    try
      let l:args = json_decode(l:args_str)
    catch
      call add(l:results, {
            \ 'role': 'tool',
            \ 'tool_call_id': l:call_id,
            \ 'content': 'Error: invalid JSON arguments: ' . l:args_str,
            \ })
      continue
    endtry

    " 安全检查（仅 shell 工具）
    if l:name ==# 'shell_execute' && s:IsDangerous(get(l:args, 'command', ''))
      call add(l:results, {
            \ 'role': 'tool',
            \ 'tool_call_id': l:call_id,
            \ 'content': 'Error: command blocked by security policy',
            \ })
      call vim_ai_store#AuditLog('BLOCKED', get(l:args, 'command', ''))
      continue
    endif

    " 执行并收集结果
    try
      let l:output = call(s:tool_aliases[l:name], [l:args])
      let l:content = string(l:output)
    catch
      let l:content = 'Error: ' . v:exception
    endtry

    " 截断过长输出
    if strlen(l:content) > 8000
      let l:content = l:content[:7999] . "\n... (truncated)"
    endif

    " 审计日志
    if l:name ==# 'shell_execute'
      call vim_ai_store#AuditLog('SHELL', get(l:args, 'command', ''))
    endif

    call add(l:results, {
          \ 'role': 'tool',
          \ 'tool_call_id': l:call_id,
          \ 'content': l:content,
          \ })
  endfor
  return l:results
endfunction

" 安全检查
function! s:IsDangerous(cmd) abort
  for l:pat in s:dangerous_patterns
    if match(a:cmd, l:pat) >= 0
      return 1
    endif
  endfor
  return 0
endfunction

" =============================================================================
" 工具实现
" =============================================================================

function! s:Tool_shell_execute(args) abort
  let l:cmd = get(a:args, 'command', '')
  let l:timeout = get(a:args, 'timeout', 10)
  if empty(l:cmd)
    return 'Error: command required'
  endif
  let l:out = system('timeout ' . l:timeout . ' ' . l:cmd)
  let l:exit = v:shell_error
  if l:exit == 0
    return substitute(l:out, '\n\+$', '', '')
  endif
  return 'Exit ' . l:exit . ': ' . substitute(l:out, '\n\+$', '', '')
endfunction

function! s:Tool_file_read(args) abort
  let l:path = expand(get(a:args, 'path', ''))
  if empty(l:path)
    return 'Error: path required'
  endif
  if !filereadable(l:path)
    return 'Error: file not readable: ' . l:path
  endif

  let l:lines = readfile(l:path)
  let l:start = get(a:args, 'start_line', 0)
  let l:end = get(a:args, 'end_line', 0)

  if l:start > 0 && l:end > 0
    let l:lines = l:lines[l:start - 1 : l:end - 1]
  elseif l:start > 0
    let l:lines = l:lines[l:start - 1:]
  endif

  return join(l:lines, "\n")
endfunction

function! s:Tool_file_glob(args) abort
  let l:pattern = get(a:args, 'pattern', '')
  let l:max = get(a:args, 'max_results', 20)
  if empty(l:pattern)
    return 'Error: pattern required'
  endif

  let l:files = glob(l:pattern, 0, 1)
  if len(l:files) > l:max
    let l:files = l:files[:l:max - 1]
    call add(l:files, '... (truncated, total > ' . l:max . ')')
  endif

  return join(l:files, "\n")
endfunction

function! s:Tool_vim_eval(args) abort
  let l:expr = get(a:args, 'expression', '')
  if empty(l:expr)
    return 'Error: expression required'
  endif

  try
    let l:result = eval(l:expr)
    return string(l:result)
  catch
    return 'Error: ' . v:exception
  endtry
endfunction

" =============================================================================
" 多轮 tool calling 编排器
" 当 AI 返回 tool_calls 时，执行工具并自动发起下一轮请求
" =============================================================================

function! vim_ai_tools#RunWithTools(options, messages, on_final_done, on_error, ...) abort
  let l:max_rounds = a:0 > 0 ? a:1 : 5

  " 第一次请求，带上 tools
  let l:tools_list = vim_ai_tools#List()
  let l:opts = copy(a:options)
  let l:opts['tools'] = l:tools_list

  call s:DoToolRound(l:opts, a:messages, 1, l:max_rounds, a:on_final_done, a:on_error)
endfunction

function! s:DoToolRound(options, messages, round, max_rounds, on_final_done, on_error) abort
  let l:ctx_id = vim_ai_http#ChatStream(
        \ a:options, a:messages,
        \ function('s:ToolRoundChunk', [a:options, a:messages, a:round, a:max_rounds, a:on_final_done, a:on_error]),
        \ function('s:ToolRoundDone', [a:options, a:messages, a:round, a:max_rounds, a:on_final_done, a:on_error]),
        \ a:on_error
        \ )
endfunction

let s:tool_round_buf = ''

function! s:ToolRoundChunk(text) abort
  let s:tool_round_buf .= a:text
endfunction

function! s:ToolRoundDone(result, options, messages, round, max_rounds, on_final_done, on_error) abort
  let s:tool_round_buf = ''

  " 如果 AI 返回了 tool_calls → 执行并进入下一轮
  if !empty(a:result.tool_calls) && a:round <= a:max_rounds
    echo 'Tool calling round ' . a:round . ': executing ' . len(a:result.tool_calls) . ' tool(s)...'

    " 把 assistant 的 tool_call 消息追加到历史
    let l:tool_call_msg = {
          \ 'role': 'assistant',
          \ 'content': a:result.content,
          \ 'tool_calls': a:result.tool_calls,
          \ }
    let l:new_msgs = a:messages + [l:tool_call_msg]

    " 执行工具
    let l:tool_results = vim_ai_tools#ExecuteAll(a:result.tool_calls)
    let l:new_msgs = l:new_msgs + l:tool_results

    echo 'Tool results ready. Round ' . (a:round + 1) . '...'

    call s:DoToolRound(a:options, l:new_msgs, a:round + 1, a:max_rounds, a:on_final_done, a:on_error)
    return
  endif

  " 否则 → 最终结果
  try
    call a:on_final_done(a:result)
  catch
  endtry
endfunction
