" =============================================================================
" Vim-AI 提示词工程模块
" 协助编写提示词的完整工作流：
"   1. 草稿模式 - 快速记录想法
"   2. 细化模式 - AI 协助完善提示词
"   3. 迭代模式 - 基于结果反馈优化
" =============================================================================

let s:prompt_history = []
let s:prompt_templates = {}
let s:prompt_state = {'mode': 'draft', 'current': '', 'refined': '', 'result': '', 'iterations': 0}

" =============================================================================
" 提示词模板库
" =============================================================================

let s:built_in_templates = {
\  'default': {
\    'name': '通用提示词',
\    'template': '你是一位专业的AI助手。请根据用户的需求提供高质量的回答。\n\n用户需求：\n{user_input}',
\    'description': '适用于大多数场景'
\  },
\  'code': {
\    'name': '代码生成',
\    'template': '你是一位资深软件工程师。请根据用户的需求编写高质量的代码。\n\n要求：\n- 代码必须可运行\n- 包含适当的注释\n- 遵循最佳实践\n- 考虑边界情况\n\n用户需求：\n{user_input}',
\    'description': '用于生成代码'
\  },
\  'review': {
\    'name': '代码审查',
\    'template': '你是一位代码审查专家。请仔细审查以下代码并提供改进建议。\n\n审查要点：\n- 代码质量和可读性\n- 潜在的 bug 和安全问题\n- 性能优化建议\n- 架构设计问题\n- 最佳实践遵循情况\n\n待审查代码：\n{code}',
\    'description': '用于代码审查'
\  },
\  'debug': {
\    'name': '调试助手',
\    'template': '你是一位调试专家。请帮助我分析以下错误并提供解决方案。\n\n错误信息：\n{error}\n\n相关代码：\n{code}\n\n已尝试的解决方案：\n{attempts}\n\n请提供：\n1. 问题根因分析\n2. 修复方案\n3. 预防措施',
\    'description': '用于调试问题'
\  },
\  'writing': {
\    'name': '写作助手',
\    'template': '你是一位专业作家。请根据用户的需求创作高质量的内容。\n\n写作要求：\n- 语言流畅自然\n- 结构清晰有条理\n- 内容详实有深度\n- 风格符合要求\n\n用户需求：\n{user_input}\n\n写作风格：{style}',
\    'description': '用于写作和内容创作'
\  },
\  'translate': {
\    'name': '翻译助手',
\    'template': '你是一位专业翻译。请将以下内容翻译成{target_language}。\n\n翻译要求：\n- 准确传达原意\n- 语言自然流畅\n- 符合目标语言习惯\n- 保持专业术语一致性\n\n待翻译内容：\n{text}',
\    'description': '用于翻译'
\  },
\  'analyze': {
\    'name': '分析助手',
\    'template': '你是一位数据分析专家。请分析以下内容并提供深入的见解。\n\n分析要求：\n- 识别关键模式和趋势\n- 提供数据驱动的见解\n- 给出可操作的建议\n- 考虑多种可能性\n\n待分析内容：\n{content}\n\n分析目标：\n{goal}',
\    'description': '用于数据分析和洞察'
\  },
\  'brainstorm': {
\    'name': '头脑风暴',
\    'template': '你是一位创意顾问。请帮助我进行头脑风暴，为以下主题提供创新想法。\n\n主题：\n{topic}\n\n约束条件：\n{constraints}\n\n请提供至少10个不同角度的创意想法，并简要说明每个想法的优势和实施建议。',
\    'description': '用于创意生成和头脑风暴'
\  }
\}

" =============================================================================
" 提示词工程命令
" =============================================================================

command! AIPrompt       call vim_ai_prompt#StartPrompt()
command! AIPromptDraft  call vim_ai_prompt#StartDraft()
command! AIPromptRefine call vim_ai_prompt#RefinePrompt()
command! AIPromptIterate call vim_ai_prompt#IteratePrompt()
command! AIPromptSave   call vim_ai_prompt#SavePrompt()
command! AIPromptLoad   call vim_ai_prompt#LoadPrompt()
command! AIPromptList   call vim_ai_prompt#ListTemplates()

" =============================================================================
" 工作流入口
" =============================================================================

function! vim_ai_prompt#StartPrompt()
  call vim_ai_prompt#StartDraft()
endfunction

function! vim_ai_prompt#StartDraft()
  let s:prompt_state = {'mode': 'draft', 'current': '', 'refined': '', 'result': '', 'iterations': 0}
  
  echo '=== 提示词草稿模式 ==='
  echo '请输入你的想法（输入 .done 结束）：'
  
  let l:lines = []
  while 1
    let l:line = input('> ')
    if l:line ==# '.done'
      break
    endif
    call add(l:lines, l:line)
  endwhile
  
  let s:prompt_state.current = join(l:lines, "\n")
  
  if empty(s:prompt_state.current)
    echo '提示词不能为空'
    return
  endif
  
  echo "\n你的草稿："
  echo s:prompt_state.current
  echo "\n是否需要 AI 协助细化？(y/n)"
  let l:choice = input('> ')
  
  if l:choice =~# '^y'
    call vim_ai_prompt#RefinePrompt()
  endif
endfunction

" =============================================================================
" 细化模式
" =============================================================================

function! vim_ai_prompt#RefinePrompt()
  if empty(s:prompt_state.current)
    echo '请先输入草稿（:AIPromptDraft）'
    return
  endif
  
  echo '=== 提示词细化模式 ==='
  echo '正在分析你的草稿并生成优化建议...'
  
  let l:refine_prompt = s:built_in_templates.brainstorm.template
  let l:refine_prompt = substitute(l:refine_prompt, '{topic}', '优化以下提示词', 'g')
  let l:refine_prompt = substitute(l:refine_prompt, '{constraints}', '让提示词更清晰、具体、可执行', 'g')
  let l:refine_prompt .= "\n\n原始提示词草稿：\n" . s:prompt_state.current
  
  let l:payload = json_encode({
    \ 'model': vim_ai_config#Get('api.model'),
    \ 'messages': [{
    \   'role': 'user',
    \   'content': l:refine_prompt
    \ }],
    \ 'temperature': 0.7
  \})
  
  let l:response = vim_ai_http#Request(
    \ vim_ai_config#Get('api.endpoint_url'),
    \ l:payload
  )
  
  if !empty(l:response)
    let s:prompt_state.refined = l:response
    echo "\nAI 优化后的提示词："
    echo l:response
    echo "\n是否使用此提示词？(y/n)"
    let l:choice = input('> ')
    if l:choice =~# '^y'
      let s:prompt_state.current = s:prompt_state.refined
    endif
  else
    echoerr '细化失败，请重试'
  endif
endfunction

" =============================================================================
" 迭代模式
" =============================================================================

function! vim_ai_prompt#IteratePrompt()
  if empty(s:prompt_state.current)
    echo '请先输入提示词（:AIPromptDraft）'
    return
  endif
  
  echo '=== 提示词迭代模式 ==='
  echo '当前提示词：'
  echo s:prompt_state.current
  echo "\n请输入上一次的结果或反馈（输入 .done 结束）："
  
  let l:lines = []
  while 1
    let l:line = input('> ')
    if l:line ==# '.done'
      break
    endif
    call add(l:lines, l:line)
  endwhile
  
  let s:prompt_state.result = join(l:lines, "\n")
  
  if empty(s:prompt_state.result)
    echo '反馈不能为空'
    return
  endif
  
  echo "\n正在分析反馈并优化提示词..."
  
  let l:iterate_prompt = "你是一位提示词工程专家。请根据原始提示词和执行结果，分析问题并优化提示词。\n\n" .
    \ "原始提示词：\n" . s:prompt_state.current . "\n\n" .
    \ "执行结果：\n" . s:prompt_state.result . "\n\n" .
    \ "请分析：\n" .
    \ "1. 提示词存在什么问题？\n" .
    \ "2. 如何改进才能获得更好的结果？\n" .
    \ "3. 输出优化后的提示词。\n\n" .
    \ "格式要求：\n" .
    \ "【问题分析】\n" .
    \ "...\n\n" .
    \ "【优化建议】\n" .
    \ "...\n\n" .
    \ "【优化后提示词】\n" .
    \ "---\n" .
    \ "{优化后的提示词}\n" .
    \ "---"
  
  let l:payload = json_encode({
    \ 'model': vim_ai_config#Get('api.model'),
    \ 'messages': [{
    \   'role': 'user',
    \   'content': l:iterate_prompt
    \ }],
    \ 'temperature': 0.5
  \})
  
  let l:response = vim_ai_http#Request(
    \ vim_ai_config#Get('api.endpoint_url'),
    \ l:payload
  )
  
  if !empty(l:response)
    let s:prompt_state.iterations += 1
    
    " 提取优化后的提示词
    let l:start = stridx(l:response, '【优化后提示词】')
    if l:start >= 0
      let l:after = l:response[l:start + 8:]
      let l:dash_start = stridx(l:after, '---')
      let l:dash_end = stridx(l:after, '---', l:dash_start + 3)
      if l:dash_start >= 0 && l:dash_end >= 0
        let l:new_prompt = l:after[l:dash_start + 3 : l:dash_end - 1]
        let s:prompt_state.current = trim(l:new_prompt)
      endif
    endif
    
    echo "\n迭代 #" . s:prompt_state.iterations . " 结果："
    echo l:response
    echo "\n是否使用优化后的提示词？(y/n)"
    let l:choice = input('> ')
    if !(l:choice =~# '^y')
      echo '保留原提示词'
    endif
  else
    echoerr '迭代失败，请重试'
  endif
endfunction

" =============================================================================
" 保存和加载提示词
" =============================================================================

function! vim_ai_prompt#SavePrompt()
  if empty(s:prompt_state.current)
    echo '没有可保存的提示词'
    return
  endif
  
  let l:name = input('请输入提示词名称：')
  if empty(l:name)
    echo '名称不能为空'
    return
  endif
  
  let l:prompt_dir = expand('~/.vim/ai_prompts')
  if !isdirectory(l:prompt_dir)
    call mkdir(l:prompt_dir, 'p')
  endif
  
  let l:filename = l:prompt_dir . '/' . l:name . '.txt'
  call writefile([s:prompt_state.current], l:filename)
  
  call add(s:prompt_history, {'name': l:name, 'path': l:filename, 'time': localtime()})
  
  echo '提示词已保存到：' . l:filename
endfunction

function! vim_ai_prompt#LoadPrompt()
  let l:prompt_dir = expand('~/.vim/ai_prompts')
  if !isdirectory(l:prompt_dir)
    echo '提示词目录不存在'
    return
  endif
  
  let l:files = glob(l:prompt_dir . '/*.txt')
  if empty(l:files)
    echo '没有保存的提示词'
    return
  endif
  
  echo '可用提示词：'
  for l:i in range(len(l:files))
    let l:name = fnamemodify(l:files[l:i], ':t:r')
    echo (l:i + 1) . '. ' . l:name
  endfor
  
  let l:choice = input('请选择提示词序号：')
  if !empty(l:choice) && str2nr(l:choice) > 0 && str2nr(l:choice) <= len(l:files)
    let l:filename = l:files[str2nr(l:choice) - 1]
    let s:prompt_state.current = join(readfile(l:filename), "\n")
    echo '提示词已加载：' . fnamemodify(l:filename, ':t:r')
    echo s:prompt_state.current
  else
    echo '无效选择'
  endif
endfunction

" =============================================================================
" 模板管理
" =============================================================================

function! vim_ai_prompt#ListTemplates()
  echo '可用提示词模板：'
  for l:key in keys(s:built_in_templates)
    let l:tpl = s:built_in_templates[l:key]
    echo '  ' . l:key . ' - ' . l:tpl.name
    echo '     ' . l:tpl.description
  endfor
  
  let l:choice = input('请输入模板名称使用：')
  if has_key(s:built_in_templates, l:choice)
    let s:prompt_state.current = s:built_in_templates[l:choice].template
    echo '模板已加载：' . s:built_in_templates[l:choice].name
    echo s:prompt_state.current
  elseif !empty(l:choice)
    echo '模板不存在'
  endif
endfunction

" =============================================================================
" 获取当前提示词
" =============================================================================

function! vim_ai_prompt#GetCurrentPrompt()
  return s:prompt_state.current
endfunction

function! vim_ai_prompt#GetPromptState()
  return s:prompt_state
endfunction