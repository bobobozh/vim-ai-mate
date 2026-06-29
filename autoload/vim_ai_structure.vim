" =============================================================================
" Vim-AI 代码结构可视化模块
" 解析代码结构，生成 PlantUML，推送到服务器实时展示
" =============================================================================

let s:structure_server_url = 'http://localhost:8765/update'
let s:structure_ws_port = 8766
let s:structure_auto_update = 1

" =============================================================================
" 代码结构解析器（基于 filetype）
" =============================================================================

function! s:ParsePythonStructure(lines)
  let l:classes = []
  let l:funcs = []
  let l:class_methods = {}
  let l:current_class = ''
  
  for l:i in range(len(a:lines))
    let l:line = a:lines[l:i]
    
    " Class 定义
    if l:line =~# '^\s*class\s+\w+'
      let l:name = matchstr(l:line, 'class\s+\zs\w+')
      call add(l:classes, {'name': l:name, 'line': l:i + 1})
      let l:current_class = l:name
      let l:class_methods[l:name] = []
    endif
    
    " Function/Method 定义
    if l:line =~# '^\s*def\s+\w+'
      let l:name = matchstr(l:line, 'def\s+\zs\w+')
      if !empty(l:current_class) && l:line =~# '^\s\s+def'
        call add(l:class_methods[l:current_class], {'name': l:name, 'line': l:i + 1})
      elseif l:line =~# '^def'
        call add(l:funcs, {'name': l:name, 'line': l:i + 1})
      endif
    endif
    
    " 退出 class
    if !empty(l:current_class) && l:line =~# '^class\|^def\|^@\w+' && l:line !~# '^\s\s+'
      let l:current_class = ''
    endif
  endfor
  
  return {'classes': l:classes, 'funcs': l:funcs, 'methods': l:class_methods}
endfunction

function! s:ParseVimscriptStructure(lines)
  let l:funcs = []
  let l:commands = []
  
  for l:i in range(len(a:lines))
    let l:line = a:lines[l:i]
    
    " Function 定义
    if l:line =~# '^function!\s+\w+#\w+'
      let l:name = matchstr(l:line, 'function!\s+\zs\w+#\w+')
      call add(l:funcs, {'name': l:name, 'line': l:i + 1})
    elseif l:line =~# '^function!\s+s:\w+'
      let l:name = matchstr(l:line, 'function!\s+s:\zs\w+')
      call add(l:funcs, {'name': '(script) ' . l:name, 'line': l:i + 1})
    endif
    
    " Command 定义
    if l:line =~# '^command!\s+-nargs'
      let l:name = matchstr(l:line, 'command!\s+\zs\w+')
      call add(l:commands, {'name': l:name, 'line': l:i + 1})
    endif
  endfor
  
  return {'funcs': l:funcs, 'commands': l:commands}
endfunction

function! s:ParseJavaScriptStructure(lines)
  let l:classes = []
  let l:funcs = []
  let l:exports = []
  
  for l:i in range(len(a:lines))
    let l:line = a:lines[l:i]
    
    " Class 定义
    if l:line =~# '^\s*class\s+\w+'
      let l:name = matchstr(l:line, 'class\s+\zs\w+')
      call add(l:classes, {'name': l:name, 'line': l:i + 1})
    endif
    
    " Function 定义
    if l:line =~# '^\s*function\s+\w+'
      let l:name = matchstr(l:line, 'function\s+\zs\w+')
      call add(l:funcs, {'name': l:name, 'line': l:i + 1})
    elseif l:line =~# '^\s*const\s+\w+\s*=\s*\([^)]*\)\s*=>'
      let l:name = matchstr(l:line, 'const\s+\zs\w+')
      call add(l:funcs, {'name': l:name . ' (arrow)', 'line': l:i + 1})
    endif
    
    " Export
    if l:line =~# '^\s*export\s+'
      let l:export = matchstr(l:line, 'export\s+\zs.*')
      call add(l:exports, {'name': l:export, 'line': l:i + 1})
    endif
  endfor
  
  return {'classes': l:classes, 'funcs': l:funcs, 'exports': l:exports}
endfunction

function! s:ParseGoStructure(lines)
  let l:structs = []
  let l:funcs = []
  let l:interfaces = []
  
  for l:i in range(len(a:lines))
    let l:line = a:lines[l:i]
    
    " Struct 定义
    if l:line =~# '^\s*type\s+\w+\s+struct'
      let l:name = matchstr(l:line, 'type\s+\zs\w+')
      call add(l:structs, {'name': l:name, 'line': l:i + 1})
    endif
    
    " Interface 定义
    if l:line =~# '^\s*type\s+\w+\s+interface'
      let l:name = matchstr(l:line, 'type\s+\zs\w+')
      call add(l:interfaces, {'name': l:name, 'line': l:i + 1})
    endif
    
    " Function 定义
    if l:line =~# '^\s*func\s+\w+'
      let l:name = matchstr(l:line, 'func\s+\zs\w+')
      call add(l:funcs, {'name': l:name, 'line': l:i + 1})
    elseif l:line =~# '^\s*func\s+(\w+)\s+\w+'
      let l:receiver = matchstr(l:line, 'func\s+(\zs\w+)')
      let l:name = matchstr(l:line, 'func\s+(\w+)\s+\zs\w+')
      call add(l:funcs, {'name': l:receiver . '.' . l:name, 'line': l:i + 1})
    endif
  endfor
  
  return {'structs': l:structs, 'funcs': l:funcs, 'interfaces': l:interfaces}
endfunction

function! s:ParseMarkdownStructure(lines)
  let l:headers = []
  
  for l:i in range(len(a:lines))
    let l:line = a:lines[l:i]
    if l:line =~# '^#\+\s+'
      let l:level = len(matchstr(l:line, '^#\+'))
      let l:title = matchstr(l:line, '^#\+\s+\zs.*')
      call add(l:headers, {'level': l:level, 'title': l:title, 'line': l:i + 1})
    endif
  endfor
  
  return {'headers': l:headers}
endfunction

" =============================================================================
" 主解析函数
" =============================================================================

function! vim_ai_structure#Parse()
  let l:ft = &filetype
  let l:lines = getline(1, '$')
  let l:filename = expand('%:t')
  let l:filepath = expand('%:p')
  
  let l:structure = {'file': l:filename, 'path': l:filepath, 'ft': l:ft}
  
  if l:ft ==# 'python'
    let l:structure.code = s:ParsePythonStructure(l:lines)
  elseif l:ft ==# 'vim'
    let l:structure.code = s:ParseVimscriptStructure(l:lines)
  elseif l:ft =~# 'javascript\|typescript'
    let l:structure.code = s:ParseJavaScriptStructure(l:lines)
  elseif l:ft ==# 'go'
    let l:structure.code = s:ParseGoStructure(l:lines)
  elseif l:ft ==# 'markdown'
    let l:structure.code = s:ParseMarkdownStructure(l:lines)
  else
    " 通用：搜索 function/class/def 等
    let l:structure.code = s:ParseGenericStructure(l:lines)
  endif
  
  return l:structure
endfunction

function! s:ParseGenericStructure(lines)
  let l:funcs = []
  let l:classes = []
  
  for l:i in range(len(a:lines))
    let l:line = a:lines[l:i]
    if l:line =~# 'function\s+\w+\|def\s+\w+\|func\s+\w+'
      let l:name = matchstr(l:line, '\zs\w+\ze\s*(')
      if !empty(l:name)
        call add(l:funcs, {'name': l:name, 'line': l:i + 1})
      endif
    endif
    if l:line =~# 'class\s+\w+'
      let l:name = matchstr(l:line, 'class\s+\zs\w+')
      call add(l:classes, {'name': l:name, 'line': l:i + 1})
    endif
  endfor
  
  return {'funcs': l:funcs, 'classes': l:classes}
endfunction

" =============================================================================
" PlantUML 生成器
" =============================================================================

function! vim_ai_structure#ToPlantUML(structure)
  let l:puml = '@startuml\n'
  let l:puml .= 'skinparam backgroundColor #1a1a2e\n'
  let l:puml .= 'skinparam handwritten false\n'
  let l:puml .= 'skinparam shadowing false\n'
  let l:puml .= 'skinparam classBackgroundColor #16213e\n'
  let l:puml .= 'skinparam classBorderColor #e94560\n'
  let l:puml .= 'skinparam classFontColor #eee\n'
  let l:puml .= 'skinparam classAttributeIconSize 0\n'
  let l:puml .= 'skinparam packageBackgroundColor #0f3460\n'
  let l:puml .= 'skinparam packageBorderColor #00cec9\n'
  let l:puml .= 'skinparam arrowColor #e94560\n'
  let l:puml .= 'skinparam noteBackgroundColor #00b894\n'
  let l:puml .= 'skinparam noteBorderColor #00b894\n'
  let l:puml .= 'skinparam noteFontColor #fff\n'
  let l:puml .= '\n'
  let l:puml .= 'title "' . a:structure.file . ' - ' . a:structure.ft . '"\n'
  let l:puml .= '\n'
  
  let l:code = a:structure.code
  
  if has_key(l:code, 'classes')
    for l:cls in l:code.classes
      let l:puml .= 'class "' . l:cls.name . '" as C_' . l:cls.name . ' {\n'
      if has_key(l:code, 'methods') && has_key(l:code.methods, l:cls.name)
        for l:m in l:code.methods[l:cls.name]
          let l:puml .= '  ' . l:m.name . '()\n'
        endfor
      endif
      let l:puml .= '}\n'
    endfor
  endif
  
  if has_key(l:code, 'funcs')
    if !empty(l:code.funcs)
      let l:puml .= 'package "Functions" {\n'
      for l:f in l:code.funcs
        let l:puml .= '  note "' . l:f.name . '" as F_' . substitute(l:f.name, '[^a-zA-Z0-9]', '_', 'g') . '\n'
      endfor
      let l:puml .= '}\n'
    endif
  endif
  
  if has_key(l:code, 'structs')
    for l:s in l:code.structs
      let l:puml .= 'class "' . l:s.name . '" as S_' . l:s.name . ' <<struct>>\n'
    endfor
  endif
  
  if has_key(l:code, 'interfaces')
    for l:i in l:code.interfaces
      let l:puml .= 'interface "' . l:i.name . '" as I_' . l:i.name . '\n'
    endfor
  endif
  
  if has_key(l:code, 'commands')
    if !empty(l:code.commands)
      let l:puml .= 'package "Commands" {\n'
      for l:c in l:code.commands
        let l:puml .= '  note "' . l:c.name . '" as Cmd_' . substitute(l:c.name, '[^a-zA-Z0-9]', '_', 'g') . '\n'
      endfor
      let l:puml .= '}\n'
    endif
  endif
  
  if has_key(l:code, 'headers')
    let l:puml .= 'package "Document Structure" {\n'
    for l:h in l:code.headers
      let l:prefix = repeat('  ', l:h.level - 1)
      let l:puml .= l:prefix . 'note "H' . l:h.level . ': ' . l:h.title . '" as H_' . l:h.line . '\n'
    endfor
    let l:puml .= '}\n'
  endif
  
  let l:puml .= '@enduml'
  
  return substitute(l:puml, '\\n', "\n", 'g')
endfunction

" =============================================================================
" 推送更新到服务器
" =============================================================================

function! vim_ai_structure#PushUpdate()
  let l:structure = vim_ai_structure#Parse()
  let l:puml = vim_ai_structure#ToPlantUML(l:structure)
  
  " 用 curl POST
  let l:payload = json_encode({'puml': l:puml, 'file': l:structure.file, 'ft': l:structure.ft})
  let l:tmpfile = tempname()
  call writefile([l:payload], l:tmpfile)
  
  let l:cmd = 'curl -s -X POST -H "Content-Type: application/json" --data-binary @' . l:tmpfile . ' ' . s:structure_server_url
  
  try
    let l:output = system(l:cmd)
    call delete(l:tmpfile)
    echo 'Structure pushed to http://localhost:8765'
  catch
    echoerr 'Failed to push structure: ' . v:exception
    call delete(l:tmpfile)
  endtry
endfunction

" =============================================================================
" 启动/停止自动更新
" =============================================================================

function! vim_ai_structure#StartAutoUpdate()
  augroup vim_ai_structure
    autocmd!
    autocmd BufWritePost * call vim_ai_structure#PushUpdate()
    autocmd BufEnter * call vim_ai_structure#PushUpdate()
  augroup END
  let s:structure_auto_update = 1
  echo 'Auto structure update enabled'
endfunction

function! vim_ai_structure#StopAutoUpdate()
  augroup vim_ai_structure
    autocmd!
  augroup END
  let s:structure_auto_update = 0
  echo 'Auto structure update disabled'
endfunction

function! vim_ai_structure#ToggleAutoUpdate()
  if s:structure_auto_update
    call vim_ai_structure#StopAutoUpdate()
  else
    call vim_ai_structure#StartAutoUpdate()
  endif
endfunction

" =============================================================================
" 命令
" =============================================================================

command! AIStructure call vim_ai_structure#PushUpdate()
command! AIStructureStart call vim_ai_structure#StartAutoUpdate()
command! AIStructureStop call vim_ai_structure#StopAutoUpdate()
command! AIStructureToggle call vim_ai_structure#ToggleAutoUpdate()
command! AIStructureServer echo 'Run: python3 ' . expand('<sfile>:p:h') . '/../tools/structure_server.py'