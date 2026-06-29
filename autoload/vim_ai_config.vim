" =============================================================================
" Vim-AI 配置集中管理
" 所有配置通过 g:vim_ai 统一管理
" =============================================================================

let s:plugin_root = expand('<sfile>:p:h:h')

" -----------------------------------------------------------------------------
" 默认配置 - 统一的配置结构
" -----------------------------------------------------------------------------
let s:default = {
\  "api": {
\    "provider": "qwen",
\    "model": "qwen-plus",
\    "endpoint_url": "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
\    "api_key_file": "~/.config/dashscope.token",
\    "timeout": 30,
\    "temperature": 0.7,
\    "top_p": 0.8,
\    "max_tokens": 0,
\  },
\  "chat": {
\    "initial_prompt": [
\      ">>> system",
\      "",
\      "You are a general assistant.",
\      "If you attach a code block add syntax type after ``` to enable syntax highlighting.",
\    ],
\    "window": {
\      "preset": "right",
\      "keep_open": 0,
\    },
\    "ui": {
\      "paste_mode": 1,
\      "code_syntax": 1,
\    },
\  },
\  "edit": {
\    "model": "qwen-turbo",
\    "endpoint_url": "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
\    "temperature": 0.1,
\    "selection_boundary": "#####",
\    "paste_mode": 1,
\  },
\  "completion": {
\    "model": "qwen-turbo",
\    "endpoint_url": "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
\    "temperature": 0.1,
\    "selection_boundary": "#####",
\    "paste_mode": 1,
\  },
\  "roles": {
\    "config_file": s:plugin_root . "/roles.ini",
\  },
\  "debug": {
\    "enabled": 0,
\    "log_file": "/tmp/vim_ai_debug.log",
\  },
\}

" -----------------------------------------------------------------------------
" 聊天窗口预设
" -----------------------------------------------------------------------------
let s:window_presets = {
\  "left":    "leftabove 50vnew | setlocal noequalalways | call vim_ai#MakeScratchWindow()",
\  "right":   "rightbelow 75vnew | setlocal noequalalways | setlocal winfixwidth | call vim_ai#MakeScratchWindow()",
\  "top":     "leftabove new | setlocal noequalalways | call vim_ai#MakeScratchWindow()",
\  "bottom":  "rightbelow new | setlocal noequalalways | call vim_ai#MakeScratchWindow()",
\  "tab":     "tabnew | call vim_ai#MakeScratchWindow()",
\  "float":   "vnew | setlocal noequalalways | call vim_ai#MakeScratchWindow()",
\}

" -----------------------------------------------------------------------------
" 初始化配置
" -----------------------------------------------------------------------------
function! s:InitConfig() abort
  " 用户配置：g:vim_ai 或 g:llm/g:ai_endpoint_url 向后兼容
  let l:user_cfg = exists("g:vim_ai") ? g:vim_ai : {}

  " 向后兼容：从旧变量读取
  if exists("g:llm") && !has_key(l:user_cfg, 'api')
    let l:user_cfg.api = get(l:user_cfg, 'api', {})
    let l:user_cfg.api.model = g:llm
  endif
  if exists("g:ai_endpoint_url") && !has_key(l:user_cfg, 'api')
    let l:user_cfg.api = get(l:user_cfg, 'api', {})
    let l:user_cfg.api.endpoint_url = g:ai_endpoint_url
  endif

  " 合并配置
  let g:vim_ai = s:DeepExtend(s:default, l:user_cfg)

  " 设置调试日志路径
  let g:vim_ai_debug = g:vim_ai.debug.enabled
  let g:vim_ai_debug_log_file = g:vim_ai.debug.log_file
endfunction

" 深度合并字典
function! s:DeepExtend(default, override) abort
  let l:result = copy(a:default)
  for [l:key, l:value] in items(a:override)
    if type(get(l:result, l:key)) == v:t_dict && type(l:value) == v:t_dict
      let l:result[l:key] = s:DeepExtend(l:result[l:key], l:value)
    else
      let l:result[l:key] = l:value
    endif
  endfor
  return l:result
endfunction

call s:InitConfig()

" -----------------------------------------------------------------------------
" 兼容性别名
" -----------------------------------------------------------------------------
let g:vim_ai_chat = g:vim_ai.chat
let g:vim_ai_edit = g:vim_ai.edit
let g:vim_ai_complete = g:vim_ai.completion
let g:vim_ai_open_chat_presets = s:window_presets
let g:vim_ai_roles_config_file = g:vim_ai.roles.config_file
let g:vim_ai_token_file_path = g:vim_ai.api.api_key_file

" -----------------------------------------------------------------------------
" 触发自动加载
" -----------------------------------------------------------------------------
function! vim_ai_config#load()
endfunction

" -----------------------------------------------------------------------------
" 深拷贝合并（供其他模块使用）
" -----------------------------------------------------------------------------
function! vim_ai_config#ExtendDeep(defaults, override) abort
  return s:DeepExtend(a:defaults, a:override)
endfunction
