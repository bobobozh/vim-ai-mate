" =============================================================================
" Vim-AI HTTP 请求模块
" 使用 curl + job 实现异步流式 SSE 请求
"
" 所有调用都是异步的，通过回调函数返回结果，不阻塞 Vim 编辑。
" =============================================================================

let s:contexts = {}

" -----------------------------------------------------------------------------
" API Key 加载
" -----------------------------------------------------------------------------
function! vim_ai_http#LoadApiKey() abort
  let l:key_file = expand(g:vim_ai.api.api_key_file)
  let l:api_key = $AI_API_KEY

  if filereadable(l:key_file)
    let l:lines = readfile(l:key_file)
    if len(l:lines) > 0
      let l:api_key = split(l:lines[0], ',')[0]
    endif
  endif

  if empty(l:api_key)
    throw 'vim_ai#MissingApiKey'
  endif

  return l:api_key
endfunction

" -----------------------------------------------------------------------------
" 发送 OpenAI 兼容的流式 chat 请求
"
" 参数:
"   options:    {model, endpoint_url, temperature, top_p, timeout, tools?}
"   messages:   [{role, content}, ...]
"   on_chunk:   funcref(text) — 每个 content delta 到达时调用
"   on_done:    funcref(result_dict) — 流结束时调用，result_dict 包含:
"                  .content    完整文本
"                  .tool_calls 工具调用列表（如果有）
"                  .usage      token 用量（如果有）
"   on_error:   funcref(err_msg)
" -----------------------------------------------------------------------------
function! vim_ai_http#ChatStream(options, messages, on_chunk, on_done, on_error) abort
  let l:api_key = vim_ai_http#LoadApiKey()

  let l:request_body = {
        \ 'model': a:options.model,
        \ 'temperature': str2float(get(a:options, 'temperature', 0.7)),
        \ 'top_p': str2float(get(a:options, 'top_p', 0.8)),
        \ 'stream': v:true,
        \ 'stream_options': {'include_usage': v:true},
        \ 'messages': a:messages,
        \ }

  " tools / tool_choice
  if has_key(a:options, 'tools') && !empty(a:options.tools)
    let l:request_body['tools'] = a:options.tools
    let l:request_body['tool_choice'] = get(a:options, 'tool_choice', 'auto')
  endif

  " max_tokens
  if has_key(a:options, 'max_tokens') && a:options.max_tokens > 0
    let l:request_body['max_tokens'] = a:options.max_tokens
  endif

  let l:json_body = json_encode(l:request_body)

  let l:tmpfile = tempname()
  call writefile([l:json_body], l:tmpfile)

  let l:curl_cmd = [
        \ 'curl', '-s', '-N',
        \ '-X', 'POST',
        \ a:options.endpoint_url,
        \ '-H', 'Content-Type: application/json',
        \ '-H', 'Authorization: Bearer ' . l:api_key,
        \ '--max-time', string(get(a:options, 'timeout', 30)),
        \ '--data-binary', '@' . l:tmpfile,
        \ ]

  let l:ctx_id = localtime() . '_' . rand()
  let s:contexts[l:ctx_id] = {
        \ 'id': l:ctx_id,
        \ 'buffer': '',
        \ 'content': '',
        \ 'tool_calls': [],
        \ 'pending_tool_calls': {},
        \ 'usage': {},
        \ 'got_usage': v:false,
        \ 'on_chunk': a:on_chunk,
        \ 'on_done': a:on_done,
        \ 'on_error': a:on_error,
        \ 'tmpfile': l:tmpfile,
        \ 'finished': v:false,
        \ 'stderr': '',
        \ 'started': v:false,
        \ }

  let l:job_opts = {
        \ 'callback': function('s:HandleStdout', [l:ctx_id]),
        \ 'err_cb': function('s:HandleStderr', [l:ctx_id]),
        \ 'exit_cb': function('s:HandleExit', [l:ctx_id]),
        \ 'mode': 'raw',
        \ }

  try
    let l:job = job_start(l:curl_cmd, l:job_opts)
    let s:contexts[l:ctx_id].job = l:job
  catch
    call delete(l:tmpfile)
    if has_key(s:contexts, l:ctx_id)
      unlet s:contexts[l:ctx_id]
    endif
    throw 'Failed to start curl job: ' . v:exception
  endtry

  return l:ctx_id
endfunction

" -----------------------------------------------------------------------------
" 发送非流式 chat 请求（仍然异步，通过回调返回完整结果）
" 用于不需要实时流式显示的场景（如 prompt 细化、工具调用回传）
"
" 参数:
"   options:  同 ChatStream
"   messages: 同 ChatStream
"   on_done:  funcref(result_dict) — {content, tool_calls, usage}
"   on_error: funcref(err_msg)
" -----------------------------------------------------------------------------
function! vim_ai_http#ChatOnce(options, messages, on_done, on_error) abort
  let l:api_key = vim_ai_http#LoadApiKey()

  let l:request_body = {
        \ 'model': a:options.model,
        \ 'temperature': str2float(get(a:options, 'temperature', 0.7)),
        \ 'top_p': str2float(get(a:options, 'top_p', 0.8)),
        \ 'stream': v:false,
        \ 'messages': a:messages,
        \ }

  if has_key(a:options, 'tools') && !empty(a:options.tools)
    let l:request_body['tools'] = a:options.tools
    let l:request_body['tool_choice'] = get(a:options, 'tool_choice', 'auto')
  endif

  if has_key(a:options, 'max_tokens') && a:options.max_tokens > 0
    let l:request_body['max_tokens'] = a:options.max_tokens
  endif

  let l:json_body = json_encode(l:request_body)

  let l:tmpfile = tempname()
  call writefile([l:json_body], l:tmpfile)

  let l:curl_cmd = [
        \ 'curl', '-s', '-N',
        \ '-X', 'POST',
        \ a:options.endpoint_url,
        \ '-H', 'Content-Type: application/json',
        \ '-H', 'Authorization: Bearer ' . l:api_key,
        \ '--max-time', string(get(a:options, 'timeout', 30)),
        \ '--data-binary', '@' . l:tmpfile,
        \ ]

  let l:ctx_id = localtime() . '_' . rand()
  let s:contexts[l:ctx_id] = {
        \ 'id': l:ctx_id,
        \ 'buffer': '',
        \ 'raw_response': '',
        \ 'is_non_stream': v:true,
        \ 'on_done': a:on_done,
        \ 'on_error': a:on_error,
        \ 'tmpfile': l:tmpfile,
        \ 'finished': v:false,
        \ 'stderr': '',
        \ }

  let l:job_opts = {
        \ 'callback': function('s:HandleStdoutNonStream', [l:ctx_id]),
        \ 'err_cb': function('s:HandleStderr', [l:ctx_id]),
        \ 'exit_cb': function('s:HandleExitNonStream', [l:ctx_id]),
        \ 'mode': 'raw',
        \ }

  try
    let l:job = job_start(l:curl_cmd, l:job_opts)
    let s:contexts[l:ctx_id].job = l:job
  catch
    call delete(l:tmpfile)
    if has_key(s:contexts, l:ctx_id)
      unlet s:contexts[l:ctx_id]
    endif
    throw 'Failed to start curl job: ' . v:exception
  endtry

  return l:ctx_id
endfunction

" =============================================================================
" 内部: SSE 流式解析
" =============================================================================

function! s:HandleStdout(ctx_id, chan, data) abort
  if !has_key(s:contexts, a:ctx_id)
    return
  endif
  let l:ctx = s:contexts[a:ctx_id]
  let l:ctx.buffer .= a:data

  let l:lines = split(l:ctx.buffer, "\n", 1)
  let l:ctx.buffer = l:lines[-1]

  for l:line in l:lines[:-2]
    let l:line = substitute(l:line, '\r$', '', '')
    if empty(l:line)
      continue
    endif

    if l:line[:5] ==# 'data: '
      let l:data = l:line[6:]
      if l:data == '[DONE]'
        if !l:ctx.finished
          let l:ctx.finished = v:true
          call s:FinalizeStreamCtx(a:ctx_id)
        endif
        return
      endif
      call s:ParseSseData(a:ctx_id, l:data)
    endif
  endfor
endfunction

function! s:ParseSseData(ctx_id, data) abort
  let l:ctx = s:contexts[a:ctx_id]
  try
    let l:resp = json_decode(a:data)
  catch
    return
  endtry

  " usage 字段（可能在单独的 chunk 里）
  if has_key(l:resp, 'usage') && !empty(l:resp.usage)
    let l:ctx.usage = l:resp.usage
    let l:ctx.got_usage = v:true
  endif

  " 选择
  if !has_key(l:resp, 'choices') || len(l:resp.choices) == 0
    return
  endif
  let l:choice = l:resp.choices[0]

  " 完整消息（第一个 chunk 可能包含 role）
  if has_key(l:choice, 'message')
    let l:msg = l:choice.message
    if has_key(l:msg, 'content') && !empty(l:msg.content)
      let l:ctx.content .= l:msg.content
      let l:ctx.started = v:true
      try
        call l:ctx.on_chunk(l:msg.content)
      catch
      endtry
    endif
    if has_key(l:msg, 'tool_calls') && !empty(l:msg.tool_calls)
      call s:MergeToolCalls(l:ctx, l:msg.tool_calls)
    endif
  endif

  " delta（流式增量）
  if has_key(l:choice, 'delta')
    let l:delta = l:choice.delta

    " content delta
    if has_key(l:delta, 'content') && !empty(l:delta.content)
      let l:ctx.content .= l:delta.content
      let l:ctx.started = v:true
      try
        call l:ctx.on_chunk(l:delta.content)
      catch
      endtry
    endif

    " tool_calls delta（增量式到达，需要累积）
    if has_key(l:delta, 'tool_calls') && !empty(l:delta.tool_calls)
      call s:MergeToolCallDeltas(l:ctx, l:delta.tool_calls)
    endif
  endif

  " finish_reason
  if has_key(l:choice, 'finish_reason') && !empty(l:choice.finish_reason)
    " 有 finish_reason 时也要触发 finalize（某些 API 不在结尾发 [DONE]）
    if !l:ctx.finished
      let l:ctx.finished = v:true
      call s:FinalizeStreamCtx(a:ctx_id)
    endif
  endif
endfunction

" 合并完整 tool_calls 列表
function! s:MergeToolCalls(ctx, tool_calls) abort
  for l:tc in a:tool_calls
    call add(a:ctx.tool_calls, l:tc)
  endfor
endfunction

" 合并增量式 tool_calls（按 index 累积）
function! s:MergeToolCallDeltas(ctx, tool_call_deltas) abort
  for l:delta in a:tool_call_deltas
    let l:idx = get(l:delta, 'index', 0)
    if !has_key(a:ctx.pending_tool_calls, l:idx)
      let a:ctx.pending_tool_calls[l:idx] = {'id': '', 'type': 'function', 'function': {'name': '', 'arguments': ''}}
    endif
    let l:acc = a:ctx.pending_tool_calls[l:idx]
    if has_key(l:delta, 'id') && !empty(l:delta.id)
      let l:acc.id .= l:delta.id
    endif
    if has_key(l:delta, 'type') && !empty(l:delta.type)
      let l:acc.type = l:delta.type
    endif
    if has_key(l:delta, 'function')
      if has_key(l:delta.function, 'name')
        let l:acc.function.name .= l:delta.function.name
      endif
      if has_key(l:delta.function, 'arguments')
        let l:acc.function.arguments .= l:delta.function.arguments
      endif
    endif
  endfor
endfunction

" 流结束时的收尾
function! s:FinalizeStreamCtx(ctx_id) abort
  if !has_key(s:contexts, a:ctx_id)
    return
  endif
  let l:ctx = s:contexts[a:ctx_id]

  " 把 pending 的 tool_call deltas 组装成完整列表
  if !empty(l:ctx.pending_tool_calls)
    for l:idx in sort(keys(l:ctx.pending_tool_calls))
      call add(l:ctx.tool_calls, l:ctx.pending_tool_calls[l:idx])
    endfor
  endif

  let l:result = {
        \ 'content': l:ctx.content,
        \ 'tool_calls': l:ctx.tool_calls,
        \ 'usage': l:ctx.usage,
        \ }

  try
    call l:ctx.on_done(l:result)
  catch
  endtry
endfunction

" =============================================================================
" 内部: 非流式解析
" =============================================================================

function! s:HandleStdoutNonStream(ctx_id, chan, data) abort
  if !has_key(s:contexts, a:ctx_id)
    return
  endif
  let s:contexts[a:ctx_id].raw_response .= a:data
endfunction

function! s:HandleExitNonStream(ctx_id, chan, exit_code) abort
  if !has_key(s:contexts, a:ctx_id)
    return
  endif
  let l:ctx = s:contexts[a:ctx_id]

  if filereadable(l:ctx.tmpfile)
    call delete(l:ctx.tmpfile)
  endif

  if a:exit_code != 0
    let l:err = 'curl error (exit ' . a:exit_code . ')'
    if !empty(l:ctx.stderr)
      let l:err .= ': ' . l:ctx.stderr
    endif
    try
      call l:ctx.on_error(l:err)
    catch
    endtry
    unlet s:contexts[a:ctx_id]
    return
  endif

  " 解析完整 JSON 响应
  try
    let l:resp = json_decode(l:ctx.raw_response)
    let l:result = {'content': '', 'tool_calls': [], 'usage': get(l:resp, 'usage', {})}
    if has_key(l:resp, 'choices') && len(l:resp.choices) > 0
      let l:msg = l:resp.choices[0].message
      let l:result.content = get(l:msg, 'content', '')
      let l:result.tool_calls = get(l:msg, 'tool_calls', [])
    endif
    try
      call l:ctx.on_done(l:result)
    catch
    endtry
  catch
    try
      call l:ctx.on_error('JSON parse failed: ' . v:exception)
    catch
    endtry
  endtry

  unlet s:contexts[a:ctx_id]
endfunction

" =============================================================================
" 内部: stderr / 通用 exit 处理（用于流式）
" =============================================================================

function! s:HandleStderr(ctx_id, chan, data) abort
  if !has_key(s:contexts, a:ctx_id)
    return
  endif
  let s:contexts[a:ctx_id].stderr .= a:data
endfunction

function! s:HandleExit(ctx_id, chan, exit_code) abort
  if !has_key(s:contexts, a:ctx_id)
    return
  endif
  let l:ctx = s:contexts[a:ctx_id]

  if filereadable(l:ctx.tmpfile)
    call delete(l:ctx.tmpfile)
  endif

  if a:exit_code != 0
    let l:err = 'curl error (exit ' . a:exit_code . ')'
    if !empty(l:ctx.stderr)
      let l:err .= ': ' . l:ctx.stderr
    endif
    if !l:ctx.finished
      l:ctx.finished = v:true
      try
        call l:ctx.on_error(l:err)
      catch
      endtry
    endif
  elseif !l:ctx.finished
    let l:ctx.finished = v:true
    call s:FinalizeStreamCtx(a:ctx_id)
  endif

  if has_key(s:contexts, a:ctx_id)
    unlet s:contexts[a:ctx_id]
  endif
endfunction

" -----------------------------------------------------------------------------
" 取消请求
" -----------------------------------------------------------------------------
function! vim_ai_http#Cancel(ctx_id) abort
  if !has_key(s:contexts, a:ctx_id)
    return
  endif
  let l:ctx = s:contexts[a:ctx_id]
  if has_key(l:ctx, 'job') && job_status(l:ctx.job) ==# 'run'
    call job_stop(l:ctx.job)
  endif
endfunction

" -----------------------------------------------------------------------------
" 调试：列出所有活跃请求
" -----------------------------------------------------------------------------
function! vim_ai_http#ListActive() abort
  let l:names = []
  for l:id in sort(keys(s:contexts))
    call add(l:names, l:id)
  endfor
  return l:names
endfunction
