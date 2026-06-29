" Ensure python3 is available
if !has('python3')
  echoerr "Python 3 support is required for vim-ai plugin"
  finish
endif

" detect if a visual selection is pending: https://stackoverflow.com/a/20133772
let g:vim_ai_is_selection_pending = 0
augroup vim_ai
  autocmd!
    autocmd CursorMoved *
          \ let g:vim_ai_is_selection_pending = mode() =~# "^[vV\<C-v>]"
augroup END

" =============================================================================
" Vim-AI 命令定义
"
" 核心命令 (5个):
"   :AI        - 通用补全/编辑（支持角色）
"   :AIChat    - 打开/继续聊天
"   :AINew     - 新建聊天
"   :AIRedo    - 重做上次命令
"   :AISet     - 显示/设置配置
"
" 使用方式:
"   :AI                    - 对当前行/选区补全
"   :AI explain this code  - 带指令的补全
"   :AI /grammar           - 使用角色
"   :AI /refactor : rust   - 使用角色并传递参数
"
"   :AIChat                - 打开聊天
"   :AIChat explain xxx     - 带初始消息的聊天
"
"   :AINew                 - 新建聊天（默认右侧窗口）
"   :AINew tab             - 在新标签页打开
"   :AINew bottom          - 在底部窗口打开
"
"   :AIRedo                - 重做上次命令
"
"   :AISet                 - 显示当前配置
"   :AISet model=gpt-4     - 设置模型
"   :AISet window=left     - 设置聊天窗口位置
" =============================================================================

command! -range   -nargs=? -complete=customlist,vim_ai#RoleCompletion AI    <line1>,<line2>call vim_ai#AIRun({}, <q-args>)
command! -range=0 -nargs=? -complete=customlist,vim_ai#RoleCompletion AIChat <line1>,<line2>call vim_ai#AIChatRun(<count>, {}, <q-args>)
command! -nargs=* -complete=customlist,vim_ai#WindowPresetCompletion AINew call vim_ai#AINewChatRun(<f-args>)
command! -nargs=0 AINewChat call vim_ai#AINewChatRun()
command! -nargs=0 AIRedo call vim_ai#AIRedoRun()
command! -nargs=? AISet call vim_ai#ShowConfig()

" =============================================================================
" 简写命令 (快捷角色)
"
" 代码相关:
"   AIp    - Explain (解释代码)
"   AIut   - Unit test (生成单元测试)
"   AIr    - Fix / Refactor (修复/重构)
"   AIw    - Write from comments (根据注释写代码)
"
" 文本相关:
"   Aen    - Improve English (改进英语表达)
"   Aten   - English tutor (英语老师，带中文解释)
"   Apro   - Professional (专业表达)
"   Aw     - 改进中文笔记
" =============================================================================

command! -range=0 -nargs=? AIp    <line1>,<line2>call vim_ai#AIChatRun(<count>, {}, "/explain")
command! -range   -nargs=? AIut   <line1>,<line2>call vim_ai#AIRun({}, "/test")
command! -range   -nargs=? AIw    <line1>,<line2>call vim_ai#AIRun({}, "/refactor")
command! -range   -nargs=? AIr    <line1>,<line2>call vim_ai#AIRun({}, "/grammar")

command! -range   -nargs=? Aen    <line1>,<line2>call vim_ai#AIRun({}, "/english")
command! -range   -nargs=? Aten   <line1>,<line2>call vim_ai#AIRun({}, "/english-tutor")
command! -range   -nargs=? Apro   <line1>,<line2>call vim_ai#AIRun({}, "/professional")
command! -range   -nargs=? Aw     <line1>,<line2>call vim_ai#AIRun({}, "/chinese")
