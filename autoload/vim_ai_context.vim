" =============================================================================
" Vim-AI 上下文提供者
" 在 AI 请求前自动收集开发环境上下文，注入到消息中让 AI 更懂当前场景
"
" 上下文包括：
"   - 当前文件元信息（路径、类型、语言）
"   - Git 状态（repo、修改文件、diff）
"   - 光标附近代码（上下文窗口）
"   - 工作目录结构概览
" =============================================================================

" 上下文收集开关（可通过 g:vim_ai.context 覆盖）
let s:default = {
\  'enabled': 1,
\  'git': {
\    'enabled': 1,
\    'max_diff_chars': 4000,
\    'include_status': 1,
\  },
\  'cursor': {
\    'enabled': 1,
\    'window_lines': 20,   " 光标前后各多少行
\  },
\  'workspace': {
\    'enabled': 1,
\    'max_files': 10,     " 列出项目中最多 N 个相关文件
\  },
\}

function! vim_ai_context#Collect() abort dict
  let l:ctx = {}
  let l:cfg = get(g:vim_ai, 'context', s:default)

  if !get(l:cfg, 'enabled', 1)
    return l:ctx
  endif

  " 1. 当前文件
  let l:ctx.file = s:CollectFileContext()

  " 2. Git
  let l:git_cfg = get(l:cfg, 'git', {})
  if get(l:git_cfg, 'enabled', 1)
    let l:ctx.git = s:CollectGitContext(l:git_cfg)
  endif

  " 3. 光标窗口
  let l:cur_cfg = get(l:cfg, 'cursor', {})
  if get(l:cur_cfg, 'enabled', 1)
    let l:ctx.cursor = s:CollectCursorContext(l:cur_cfg)
  endif

  return l:ctx
endfunction

" -----------------------------------------------------------------------------
" 1. 当前文件上下文
" -----------------------------------------------------------------------------
function! s:CollectFileContext() abort dict
  let l:ft = &filetype
  let l:filename = expand('%:t')
  let l:filepath = expand('%:p')
  let l:line_count = line('$')
  let l:cursor_line = line('.')
  let l:cursor_col = col('.')

  let l:lang_map = {
        \ 'python': 'Python',
        \ 'go': 'Go',
        \ 'javascript': 'JavaScript',
        \ 'typescript': 'TypeScript',
        \ 'java': 'Java',
        \ 'rust': 'Rust',
        \ 'c': 'C',
        \ 'cpp': 'C++',
        \ 'html': 'HTML',
        \ 'css': 'CSS',
        \ 'vim': 'Vimscript',
        \ 'sh': 'Shell',
        \ 'markdown': 'Markdown',
        \ 'yaml': 'YAML',
        \ 'json': 'JSON',
        \ 'toml': 'TOML',
        \ }
  let l:language = get(l:lang_map, l:ft, l:ft)

  return {
        \ 'filename': l:filename,
        \ 'filepath': l:filepath,
        \ 'filetype': l:ft,
        \ 'language': l:language,
        \ 'line_count': l:line_count,
        \ 'cursor': {'line': l:cursor_line, 'col': l:cursor_col},
        \ }
endfunction

" -----------------------------------------------------------------------------
" 2. Git 上下文
" -----------------------------------------------------------------------------
function! s:CollectGitContext(cfg) abort dict
  let l:git_dir = s:RunCmd('git rev-parse --show-toplevel 2>/dev/null')
  if empty(l:git_dir)
    return {}
  endif

  let l:ctx = {'repo': l:git_dir}

  " 当前分支
  let l:branch = s:RunCmd('git rev-parse --abbrev-ref HEAD 2>/dev/null')
  if !empty(l:branch)
    let l:ctx.branch = l:branch
  endif

  " 改动文件列表
  if get(a:cfg, 'include_status', 1)
    let l:status = s:RunCmd('git status --short 2>/dev/null')
    if !empty(l:status)
      let l:ctx.status = split(l:status, "\n")
    endif
  endif

  " 当前文件的 staged + unstaged diff（截断）
  let l:max = get(a:cfg, 'max_diff_chars', 4000)
  let l:rel = fnamemodify(expand('%'), ':p') ==# expand('%') ? expand('%') : fnamemodify(expand('%'), ':p')
  let l:diff = s:RunCmd('git diff -- ' . shellescape(l:rel) . ' 2>/dev/null')
  if empty(l:diff)
    let l:diff = s:RunCmd('git diff HEAD -- ' . shellescape(l:rel) . ' 2>/dev/null')
  endif
  if !empty(l:diff)
    if strlen(l:diff) > l:max
      let l:diff = l:diff[: l:max - 1] . "\n... (diff truncated)"
    endif
    let l:ctx.diff = l:diff
  endif

  return l:ctx
endfunction

" -----------------------------------------------------------------------------
" 3. 光标附近代码窗口
" -----------------------------------------------------------------------------
function! s:CollectCursorContext(cfg) abort dict
  let l:half = get(a:cfg, 'window_lines', 20)
  let l:cur = line('.')
  let l:first = max([1, l:cur - l:half])
  let l:last = min([line('$'), l:cur + l:half])

  let l:lines = getline(l:first, l:last)
  let l:numbered = []
  let l:idx = l:first
  for l:l in l:lines
    let l:prefix = l:idx ==# l:cur ? '>' : ' '
    call add(l:numbered, printf('%s%4d: %s', l:prefix, l:idx, l:l))
    let l:idx += 1
  endfor

  return {
        \ 'range': [l:first, l:last],
        \ 'content': join(l:numbered, "\n"),
        \ }
endfunction

" -----------------------------------------------------------------------------
" 辅助：运行 shell 命令并返回 stdout
" -----------------------------------------------------------------------------
function! s:RunCmd(cmd) abort
  try
    let l:out = system(a:cmd)
    return substitute(l:out, '\n\+$', '', '')
  catch
    return ''
  endtry
endfunction

" =============================================================================
" 组装成可注入的 system message 片段
" =============================================================================

function! vim_ai_context#BuildSystemSnippet() abort
  let l:ctx = vim_ai_context#Collect()
  let l:lines = ['[开发环境上下文]']

  if has_key(l:ctx, 'file')
    let l:f = l:ctx.file
    call add(l:lines, printf('文件: %s (%s, %d 行)', l:f.filename, l:f.language, l:f.line_count))
    call add(l:lines, printf('光标: 第 %d 行', l:f.cursor.line))
  endif

  if has_key(l:ctx, 'git') && !empty(l:ctx.git)
    let l:g = l:ctx.git
    if has_key(l:g, 'branch')
      call add(l:lines, printf('Git: %s@%s', fnamemodify(l:g.repo, ':t'), l:g.branch))
    endif
    if has_key(l:g, 'status') && !empty(l:g.status)
      call add(l:lines, '改动文件:')
      for l:s in l:g.status[:9]
        call add(l:lines, '  ' . l:s)
      endfor
      if len(l:g.status) > 10
        call add(l:lines, '  ... 等 ' . len(l:g.status) . ' 个文件')
      endif
    endif
    if has_key(l:g, 'diff') && !empty(l:g.diff)
      call add(l:lines, '')
      call add(l:lines, '当前文件 diff:')
      call add(l:lines, l:g.diff)
    endif
  endif

  if has_key(l:ctx, 'cursor') && !empty(l:ctx.cursor.content)
    call add(l:lines, '')
    call add(l:lines, '光标附近代码 (' . l:ctx.cursor.range[0] . '-' . l:ctx.cursor.range[1] . ', > 标记光标行):')
    call add(l:lines, l:ctx.cursor.content)
  endif

  return join(l:lines, "\n")
endfunction

" =============================================================================
" 将上下文注入到消息列表的最前面（system 之后）
" =============================================================================

function! vim_ai_context#Inject(messages) abort
  let l:snippet = vim_ai_context#BuildSystemSnippet()
  if empty(l:snippet)
    return a:messages
  endif

  let l:new_msgs = []
  let l:injected = 0
  for l:msg in a:messages
    call add(l:new_msgs, l:msg)
    if !l:injected && l:msg.role ==# 'system'
      call add(l:new_msgs, {'role': 'system', 'content': l:snippet})
      let l:injected = 1
    endif
  endfor

  if !l:injected
    call insert(l:new_msgs, {'role': 'system', 'content': l:snippet}, 0)
  endif

  return l:new_msgs
endfunction
