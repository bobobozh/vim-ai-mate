" =============================================================================
" Vim-AI HTTP 请求模块
" 使用 curl + job 实现流式 SSE 请求
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
" -----------------------------------------------------------------------------
function! vim_ai_http#ChatStream(options, messages, on_chunk, on_done, on_error) abort
  let l:api_key = vim_ai_http#LoadApiKey()

  let l:request_body = {
        \ 'model': a:options.model,
        \ 'temperature': str2float(a:options.temperature),
        \ 'top_p': str2float(a:options.top_p),
        \ 'stream': v:true,
        \ 'stream_options': {'include_usage': v:false},
        \ 'messages': a:messages,
        \ }

  let l:json_body = json_encode(l:request_body)

  " 用临时文件存请求体
  let l:tmpfile = tempname()
  call writefile([l:json_body], l:tmpfile)

  let l:curl_cmd = [
        \ 'curl', '-s', '-N',
        \ '-X', 'POST',
        \ a:options.endpoint_url,
        \ '-H', 'Content-Type: application/json',
        \ '-H', 'Authorization: Bearer ' . l:api_key,
        \ '--max-time', string(a:options.timeout),
        \ '--data-binary', '@' . l:tmpfile,
        \ ]

  let l:ctx_id = localtime() . '_' . rand()
  let s:contexts[l:ctx_id] = {
        \ 'id': l:ctx_id,
        \ 'buffer': '',
        \ 'on_chunk': a:on_chunk,
        \ 'on_done': a:on_done,
        \ 'on_error': a:on_error,
        \ 'tmpfile': l:tmpfile,
        \ 'finished': v:false,
        \ 'stderr': '',
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
" 内部: 处理 stdout
" -----------------------------------------------------------------------------
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
          call l:ctx.on_done()
        endif
        return
      endif
      try
        let l:resp = json_decode(l:data)
        if has_key(l:resp, 'choices') && len(l:resp.choices) > 0
          let l:delta = l:resp.choices[0].delta
          if type(l:delta) == type({}) && has_key(l:delta, 'content')
            call l:ctx.on_chunk(l:delta.content)
          endif
        endif
      catch
        " 忽略无效的 JSON 行
      endtry
    endif
  endfor
endfunction

" -----------------------------------------------------------------------------
" 内部: 处理 stderr
" -----------------------------------------------------------------------------
function! s:HandleStderr(ctx_id, chan, data) abort
  if !has_key(s:contexts, a:ctx_id)
    return
  endif
  let s:contexts[a:ctx_id].stderr .= a:data
endfunction

" -----------------------------------------------------------------------------
" 内部: 处理退出
" -----------------------------------------------------------------------------
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
    call l:ctx.on_error(l:err)
  elseif !l:ctx.finished
    let l:ctx.finished = v:true
    call l:ctx.on_done()
  endif

  unlet s:contexts[a:ctx_id]
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
