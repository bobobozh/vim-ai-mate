" =============================================================================
" Vim-AI 持久化存储模块
" 统一管理所有需要落盘的数据：对话历史、提示词、表达积累、审计日志
" =============================================================================

let s:store_root = expand('~/.vim/ai_store')
let s:subdirs = {
\  'conversations': 'conversations',
\  'prompts':       'prompts',
\  'expressions':   'expressions',
\  'audit':         'audit',
\}

" -----------------------------------------------------------------------------
" 获取存储根目录（可通过 g:vim_ai.store_root 覆盖）
" -----------------------------------------------------------------------------
function! vim_ai_store#Root() abort
  let l:cfg_root = get(g:vim_ai, 'store_root', '')
  if !empty(l:cfg_root)
    return expand(l:cfg_root)
  endif
  return s:store_root
endfunction

" -----------------------------------------------------------------------------
" 获取某个子目录的完整路径（自动创建）
" vim_ai_store#Path('conversations') → ~/.vim/ai_store/conversations/
" vim_ai_store#Path('prompts')       → ~/.vim/ai_store/prompts/
" -----------------------------------------------------------------------------
function! vim_ai_store#Path(name) abort
  let l:sub = get(s:subdirs, a:name, a:name)
  let l:dir = vim_ai_store#Root() . '/' . l:sub
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  return l:dir
endfunction

" =============================================================================
" 对话历史持久化
" =============================================================================

" 生成对话文件名（基于时间戳 + 可选标签）
function! s:ConversationFilename(tag) abort
  let l:ts = strftime('%Y%m%d_%H%M%S')
  let l:tag = substitute(a:tag, '[^a-zA-Z0-9_-]', '_', 'g')
  if empty(l:tag)
    return 'chat_' . l:ts . '.json'
  endif
  return 'chat_' . l:ts . '_' . l:tag . '.json'
endfunction

" 保存对话（消息列表 + 元信息）
" messages: [{role, content}, ...]
" meta: {model, created_at, ...}
function! vim_ai_store#SaveConversation(messages, meta, ...) abort
  let l:tag = a:0 > 0 ? a:1 : ''
  let l:dir = vim_ai_store#Path('conversations')
  let l:file = l:dir . '/' . s:ConversationFilename(l:tag)

  let l:payload = {
        \ 'version': 1,
        \ 'messages': a:messages,
        \ 'meta': extend({'created_at': strftime('%Y-%m-%dT%H:%M:%S'), 'model': ''}, a:meta),
        \ }

  call writefile([json_encode(l:payload)], l:file)
  return l:file
endfunction

" 列出所有对话文件（按时间倒序）
function! vim_ai_store#ListConversations() abort
  let l:dir = vim_ai_store#Path('conversations')
  let l:files = sort(glob(l:dir . '/chat_*.json'))
  call reverse(l:files)
  return l:files
endfunction

" 加载指定对话文件
function! vim_ai_store#LoadConversation(filepath) abort
  if !filereadable(a:filepath)
    return {}
  endif
  let l:lines = readfile(a:filepath)
  let l:json = join(l:lines, "\n")
  try
    return json_decode(l:json)
  catch
    return {}
  endtry
endfunction

" 加载最近 N 条对话
function! vim_ai_store#LoadRecent(count) abort
  let l:files = vim_ai_store#ListConversations()
  let l:result = []
  let l:n = min([a:count, len(l:files)])
  for l:i in range(l:n)
    let l:data = vim_ai_store#LoadConversation(l:files[l:i])
    if !empty(l:data)
      call add(l:result, {'file': l:files[l:i], 'data': l:data})
    endif
  endfor
  return l:result
endfunction

" 删除对话文件
function! vim_ai_store#DeleteConversation(filepath) abort
  if filereadable(a:filepath)
    call delete(a:filepath)
    return 1
  endif
  return 0
endfunction

" =============================================================================
" 审计日志（记录 AI 执行的 shell 命令等危险操作）
" =============================================================================

function! vim_ai_store#AuditLog(action, detail) abort
  let l:dir = vim_ai_store#Path('audit')
  let l:logfile = l:dir . '/audit_' . strftime('%Y%m%d') . '.log'
  let l:line = strftime('%Y-%m-%d %H:%M:%S') . ' [' . a:action . '] ' . a:detail
  call writefile([l:line], l:logfile, 'a')
endfunction
