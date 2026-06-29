" =============================================================================
" Vim-AI 代码结构可视化模块
" 解析代码结构，在 Vim split 窗口中显示结构树
" 光标位置自动同步高亮并居中
" =============================================================================

let s:structure_auto_update = 0
let s:structure_win_name = 'AI-Structure'
let s:structure_bufnr = -1
let s:structure_source_bufnr = -1
let s:structure_items = []

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
      call add(l:headers, {'level': l:level, 'title': l:title, 'name': l:title, 'line': l:i + 1})
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
" 命令
" =============================================================================

command! AIStructure call vim_ai_structure#ToggleWindow()
command! AIStructureOpen call vim_ai_structure#OpenWindow()
command! AIStructureClose call vim_ai_structure#CloseWindow()
command! AIStructureRefresh call vim_ai_structure#RefreshWindow()

" =============================================================================
" 结构树视图窗口管理
" =============================================================================

function! vim_ai_structure#ToggleWindow()
  if s:structure_bufnr >= 0 && bufexists(s:structure_bufnr)
    let l:wins = win_findbuf(s:structure_bufnr)
    if !empty(l:wins)
      call win_gotoid(l:wins[0])
      close
      return
    endif
  endif
  call vim_ai_structure#OpenWindow()
endfunction

function! vim_ai_structure#OpenWindow()
  let s:structure_source_bufnr = bufnr('%')
  
  " 创建右侧窗口
  rightbelow 30vnew
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal noswapfile
  setlocal nobuflisted
  setlocal nonumber
  setlocal norelativenumber
  setlocal nowrap
  setlocal winfixwidth
  setlocal cursorline
  setlocal filetype=aistructure
  
  let s:structure_bufnr = bufnr('%')
  silent! file `=s:structure_win_name`
  
  " 设置语法高亮
  call s:SetupSyntax()
  
  " 设置按键映射
  call s:SetupMappings()
  
  " 渲染结构树
  call vim_ai_structure#RefreshWindow()
  
  " 返回原窗口
  wincmd p
  
  " 设置自动同步
  augroup vim_ai_structure_sync
    autocmd!
    autocmd CursorHold,CursorHoldI <buffer> call vim_ai_structure#SyncCursor()
    autocmd BufWritePost <buffer> call vim_ai_structure#RefreshWindow()
  augroup END
endfunction

function! vim_ai_structure#CloseWindow()
  if s:structure_bufnr >= 0 && bufexists(s:structure_bufnr)
    let l:wins = win_findbuf(s:structure_bufnr)
    if !empty(l:wins)
      call win_gotoid(l:wins[0])
      close
    endif
  endif
endfunction

function! vim_ai_structure#RefreshWindow()
  if s:structure_bufnr < 0 || !bufexists(s:structure_bufnr)
    return
  endif
  
  let l:structure = vim_ai_structure#Parse()
  let l:lines = []
  let s:structure_items = []
  
  let l:code = l:structure.code
  
  " 文件标题
  call add(l:lines, '┌─ ' . l:structure.file . ' ─────────────────')
  call add(l:lines, '│ ft: ' . l:structure.ft)
  call add(l:lines, '│')
  
  " Classes
  if has_key(l:code, 'classes') && !empty(l:code.classes)
    call add(l:lines, '│ ▶ Classes')
    for l:cls in l:code.classes
      call add(l:lines, '│   ├─ class ' . l:cls.name . ' [' . l:cls.line . ']')
      call add(s:structure_items, {'name': l:cls.name, 'line': l:cls.line, 'type': 'class', 'indent': 2})
      if has_key(l:code, 'methods') && has_key(l:code.methods, l:cls.name)
        for l:m in l:code.methods[l:cls.name]
          call add(l:lines, '│   │  └─ ' . l:m.name . ' [' . l:m.line . ']')
          call add(s:structure_items, {'name': l:m.name, 'line': l:m.line, 'type': 'method', 'indent': 3})
        endfor
      endif
    endfor
    call add(l:lines, '│')
  endif
  
  " Functions
  if has_key(l:code, 'funcs') && !empty(l:code.funcs)
    call add(l:lines, '│ ▶ Functions')
    for l:f in l:code.funcs
      call add(l:lines, '│   └─ ' . l:f.name . ' [' . l:f.line . ']')
      call add(s:structure_items, {'name': l:f.name, 'line': l:f.line, 'type': 'function', 'indent': 2})
    endfor
    call add(l:lines, '│')
  endif
  
  " Structs (Go)
  if has_key(l:code, 'structs') && !empty(l:code.structs)
    call add(l:lines, '│ ▶ Structs')
    for l:s in l:code.structs
      call add(l:lines, '│   └─ struct ' . l:s.name . ' [' . l:s.line . ']')
      call add(s:structure_items, {'name': l:s.name, 'line': l:s.line, 'type': 'struct', 'indent': 2})
    endfor
    call add(l:lines, '│')
  endif
  
  " Interfaces (Go)
  if has_key(l:code, 'interfaces') && !empty(l:code.interfaces)
    call add(l:lines, '│ ▶ Interfaces')
    for l:i in l:code.interfaces
      call add(l:lines, '│   └─ interface ' . l:i.name . ' [' . l:i.line . ']')
      call add(s:structure_items, {'name': l:i.name, 'line': l:i.line, 'type': 'interface', 'indent': 2})
    endfor
    call add(l:lines, '│')
  endif
  
  " Commands (Vimscript)
  if has_key(l:code, 'commands') && !empty(l:code.commands)
    call add(l:lines, '│ ▶ Commands')
    for l:c in l:code.commands
      call add(l:lines, '│   └─ ' . l:c.name . ' [' . l:c.line . ']')
      call add(s:structure_items, {'name': l:c.name, 'line': l:c.line, 'type': 'command', 'indent': 2})
    endfor
    call add(l:lines, '│')
  endif
  
  " Headers (Markdown)
  if has_key(l:code, 'headers') && !empty(l:code.headers)
    call add(l:lines, '│ ▶ Document')
    for l:h in l:code.headers
      let l:indent = repeat('  ', l:h.level)
      call add(l:lines, '│   ' . l:indent . 'H' . l:h.level . ': ' . l:h.title . ' [' . l:h.line . ']')
      call add(s:structure_items, {'name': l:h.title, 'line': l:h.line, 'type': 'header', 'indent': l:h.level})
    endfor
    call add(l:lines, '│')
  endif
  
  call add(l:lines, '└───────────────────────────────')
  
  " 写入 buffer
  let l:win = bufwinnr(s:structure_bufnr)
  if l:win >= 0
    call setbufvar(s:structure_bufnr, '&modifiable', 1)
    call s:BufSetLines(s:structure_bufnr, 0, -1, 0, l:lines)
    call setbufvar(s:structure_bufnr, '&modifiable', 0)
  endif
  
  " 同步当前光标位置
  call vim_ai_structure#SyncCursor()
endfunction

function! s:BufSetLines(buf, start, end, keep, lines)
  if has('nvim')
    call nvim_buf_set_lines(a:buf, a:start, a:end, a:keep, a:lines)
  else
    " Vim8 兼容方式
    let l:win = bufwinnr(a:buf)
    if l:win >= 0
      execute l:win . 'wincmd w'
      execute a:start + 1 . ',' . (a:end < 0 ? line('$') : a:end + 1) . 'delete'
      call append(a:start - 1, a:lines)
      wincmd p
    endif
  endif
endfunction

function! vim_ai_structure#SyncCursor()
  if s:structure_bufnr < 0 || !bufexists(s:structure_bufnr)
    return
  endif
  
  let l:source_line = line('.')
  let l:closest_item = {'line': 1}
  let l:closest_idx = 1
  
  " 找到离当前行最近的结构元素
  for l:idx in range(len(s:structure_items))
    let l:item = s:structure_items[l:idx]
    if l:item.line <= l:source_line && l:item.line >= l:closest_item.line
      let l:closest_item = l:item
      let l:closest_idx = l:idx + 4  " 偏移量（标题行数）
    endif
  endfor
  
  " 在结构窗口中定位并居中
  let l:win = bufwinnr(s:structure_bufnr)
  if l:win >= 0
    let l:winid = win_getid(l:win)
    call win_gotoid(l:winid)
    execute 'normal! ' . l:closest_idx . 'G'
    normal! zz
    wincmd p
  endif
endfunction

function! s:SetupSyntax()
  syntax match AIStructureTitle /^┌─.*$/ contains=AIStructureFileName
  syntax match AIStructureFileName /\S\+/ contained
  syntax match AIStructureFooter /^└─.*$/
  syntax match AIStructureSection /^│ ▶.*$/
  syntax match AIStructureItem /^│.*├─.*$/ contains=AIStructureClass,AIStructureLineNum
  syntax match AIStructureItem /^│.*└─.*$/ contains=AIStructureFunc,AIStructureMethod,AIStructureLineNum
  syntax match AIStructureClass /class \w\+/ contained
  syntax match AIStructureFunc /\w\+/ contained
  syntax match AIStructureMethod /\w\+/ contained
  syntax match AIStructureLineNum /\[\d\+\]/ contained
  syntax match AIStructureTree /^│/
  
  highlight AIStructureTitle ctermfg=11 gui_foreground=#00cec9
  highlight AIStructureFileName ctermfg=14 gui_foreground=#e94560
  highlight AIStructureFooter ctermfg=11 gui_foreground=#00cec9
  highlight AIStructureSection ctermfg=13 gui_foreground=#fdcb6e
  highlight AIStructureClass ctermfg=12 gui_foreground=#74b9ff
  highlight AIStructureFunc ctermfg=10 gui_foreground=#00b894
  highlight AIStructureMethod ctermfg=14 gui_foreground=#a29bfe
  highlight AIStructureLineNum ctermfg=8 gui_foreground=#636e72
  highlight AIStructureTree ctermfg=8 gui_foreground=#636e72
endfunction

function! s:SetupMappings()
  " 回车跳转到代码位置
  nnoremap <buffer> <CR> :call <SID>JumpToLine()<CR>
  
  " 刷新
  nnoremap <buffer> r :call vim_ai_structure#RefreshWindow()<CR>
  
  " 关闭
  nnoremap <buffer> q :close<CR>
  
  " 切换到源文件
  nnoremap <buffer> <Tab> :wincmd p<CR>
endfunction

function! s:JumpToLine()
  let l:cur_line = line('.')
  
  " 从当前行解析行号 [xxx]
  let l:text = getline(l:cur_line)
  let l:num_match = matchstr(l:text, '\[\zs\d\+\ze\]')
  
  if !empty(l:num_match)
    let l:target_line = str2nr(l:num_match)
    wincmd p
    execute 'normal! ' . l:target_line . 'G'
    normal! zz
  endif
endfunction