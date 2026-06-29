" =============================================================================
" Vim-AI 角色配置模块（纯 Vimscript 实现）
" 解析 ini 格式的角色配置文件
" =============================================================================

let s:plugin_root = expand('<sfile>:p:h:h')
let s:roles_cache = {}
let s:roles_cache_time = 0

" -----------------------------------------------------------------------------
" 解析 ini 文件为字典
" 支持:
"   [section]
"   key = value
"   key = multi
"         line
"         value
" -----------------------------------------------------------------------------
function! vim_ai_roles#ParseIni(filepath) abort
  let l:filepath = expand(a:filepath)
  if !filereadable(l:filepath)
    throw 'Role config file does not exist: ' . l:filepath
  endif

  let l:lines = readfile(l:filepath)
  let l:result = {}
  let l:current_section = ''

  for l:line in l:lines
    let l:line = substitute(l:line, '\r$', '', '')

    " 跳过空行和注释
    if empty(l:line) || l:line[0] ==# ';' || l:line[0] ==# '#'
      continue
    endif

    " 节标题
    if l:line[0] ==# '[' && l:line[-1] ==# ']'
      let l:current_section = l:line[1:-2]
      if !has_key(l:result, l:current_section)
        let l:result[l:current_section] = {}
      endif
      continue
    endif

    " 键值对
    let l:eq_pos = stridx(l:line, '=')
    if l:eq_pos > 0
      let l:key = trim(l:line[:l:eq_pos - 1])
      let l:value = trim(l:line[l:eq_pos + 1:])
      if has_key(l:result, l:current_section)
        let l:result[l:current_section][l:key] = l:value
      endif
      continue
    endif

    " 续行（上一行的值继续）
    if !empty(l:current_section) && has_key(l:result, l:current_section)
      let l:section = l:result[l:current_section]
      if !empty(l:section)
        let l:keys = keys(l:section)
        let l:last_key = l:keys[-1]
        let l:section[l:last_key] .= "\n" . trim(l:line)
      endif
    endif
  endfor

  return l:result
endfunction

" -----------------------------------------------------------------------------
" 加载角色配置（带缓存）
" -----------------------------------------------------------------------------
function! vim_ai_roles#Load() abort
  let l:filepath = expand(g:vim_ai.roles.config_file)
  let l:mtime = getftime(l:filepath)

  if has_key(s:roles_cache, l:filepath) && s:roles_cache_time[l:filepath] >= l:mtime
    return s:roles_cache[l:filepath]
  endif

  let l:roles = vim_ai_roles#ParseIni(l:filepath)

  " 应用自定义角色函数
  if exists('g:vim_ai_roles_config_function')
    let l:fn = g:vim_ai_roles_config_function
    if exists('*' . l:fn)
      let l:custom = call(l:fn)
      if type(l:custom) == type({})
        for [l:k, l:v] in items(l:custom)
          let l:roles[l:k] = l:v
        endfor
      endif
    endif
  endif

  let s:roles_cache[l:filepath] = l:roles
  let s:roles_cache_time = {}
  let s:roles_cache_time[l:filepath] = l:mtime

  return l:roles
endfunction

" -----------------------------------------------------------------------------
" 获取所有角色名称
" -----------------------------------------------------------------------------
function! vim_ai_roles#GetNames() abort
  let l:roles = vim_ai_roles#Load()
  let l:names = []
  for l:name in keys(l:roles)
    if l:name !~# '\.'
      call add(l:names, l:name)
    endif
  endfor
  return sort(l:names)
endfunction

" -----------------------------------------------------------------------------
" 获取指定角色的配置
" 返回:
"   {
"     'role': {'prompt': '...', ...},
"     'options': {
"       'options_default': {},
"       'options_complete': {},
"       'options_chat': {},
"     }
"   }
" -----------------------------------------------------------------------------
function! vim_ai_roles#Get(role) abort
  let l:roles = vim_ai_roles#Load()

  if !has_key(l:roles, a:role)
    throw 'Role not found: ' . a:role
  endif

  let l:opts_key = a:role . '.options'
  let l:opts_complete_key = a:role . '.options-complete'
  let l:opts_chat_key = a:role . '.options-chat'

  return {
        \ 'role': copy(l:roles[a:role]),
        \ 'options': {
        \   'options_default': has_key(l:roles, l:opts_key) ? copy(l:roles[l:opts_key]) : {},
        \   'options_complete': has_key(l:roles, l:opts_complete_key) ? copy(l:roles[l:opts_complete_key]) : {},
        \   'options_chat': has_key(l:roles, l:opts_chat_key) ? copy(l:roles[l:opts_chat_key]) : {},
        \ },
        \ }
endfunction

" -----------------------------------------------------------------------------
" 解析提示词和角色
" 输入: '/rolename some text' 或 'just some text'
" 返回: [prompt, role_options_dict]
" -----------------------------------------------------------------------------
function! vim_ai_roles#ParsePrompt(raw_prompt) abort
  let l:prompt = trim(a:raw_prompt)
  if empty(l:prompt)
    return [l:prompt, {'options_default': {}, 'options_complete': {}, 'options_chat': {}}]
  endif

  let l:first_word = split(l:prompt, ' ')[0]
  if l:first_word[0] !=# '/'
    " 没有角色前缀
    return [l:prompt, {'options_default': {}, 'options_complete': {}, 'options_chat': {}}]
  endif

  " 提取角色名（去掉开头的 /）
  let l:role_name = l:first_word[1:]
  let l:rest = l:prompt[len(l:first_word):]
  let l:rest = trim(l:rest)

  " 去掉可能的冒号
  if len(l:rest) > 0 && l:rest[0] ==# ':'
    let l:rest = trim(l:rest[1:])
  endif

  try
    let l:role_config = vim_ai_roles#Get(l:role_name)
  catch
    " 角色不存在，把整个当普通提示词
    return [l:prompt, {'options_default': {}, 'options_complete': {}, 'options_chat': {}}]
  endtry

  " 组合角色 prompt 和用户输入
  let l:role_prompt = get(l:role_config.role, 'prompt', '')
  if !empty(l:role_prompt) && !empty(l:rest)
    let l:prompt = l:role_prompt . ":\n" . l:rest
  elseif !empty(l:role_prompt)
    let l:prompt = l:role_prompt
  else
    let l:prompt = l:rest
  endif

  return [l:prompt, l:role_config.options]
endfunction
