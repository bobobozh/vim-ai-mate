" =============================================================================
" Vim-AI 插件入口（纯 Vimscript 版本）
" 基于 curl + job 的异步流式请求
" =============================================================================

" 检查 Vim 版本（需要 job_start 和 json_decode）
if !has('job')
  echoerr "Vim with job support is required (Vim 8.0+)"
  finish
endif

" 检测视觉选区状态
let g:vim_ai_is_selection_pending = 0
augroup vim_ai
  autocmd!
    autocmd CursorMoved *
          \ let g:vim_ai_is_selection_pending = mode() =~# "^[vV\<C-v>]"
augroup END

" =============================================================================
" 核心命令
" =============================================================================

command! -range   -nargs=? -complete=customlist,vim_ai#RoleCompletion AI      <line1>,<line2>call vim_ai#AIRun({}, <q-args>)
command! -range=0 -nargs=? -complete=customlist,vim_ai#RoleCompletion AIChat  <line1>,<line2>call vim_ai#AIChatRun(<count>, {}, <q-args>)
command! -nargs=* -complete=customlist,vim_ai#WindowPresetCompletion AINew    call vim_ai#AINewChatRun(<f-args>)
command! -nargs=0 AINewChat call vim_ai#AINewChatRun()
command! -nargs=0 AIRedo    call vim_ai#AIRedoRun()
command! -nargs=? AISet     call vim_ai#ShowConfig()

" =============================================================================
" 简写命令
" =============================================================================

command! -range=0 -nargs=? AIp    <line1>,<line2>call vim_ai#AIChatRun(<count>, {}, "/explain")
command! -range   -nargs=? AIut   <line1>,<line2>call vim_ai#AIRun({}, "/test")
command! -range   -nargs=? AIw    <line1>,<line2>call vim_ai#AIRun({}, "/refactor")
command! -range   -nargs=? AIr    <line1>,<line2>call vim_ai#AIRun({}, "/grammar")

command! -range   -nargs=? Aen    <line1>,<line2>call vim_ai#AIRun({}, "/english")
command! -range   -nargs=? Aten   <line1>,<line2>call vim_ai#AIRun({}, "/english-tutor")
command! -range   -nargs=? Apro   <line1>,<line2>call vim_ai#AIRun({}, "/professional")
command! -range   -nargs=? Aw     <line1>,<line2>call vim_ai#AIRun({}, "/chinese")
command! -range   -nargs=? AIv    <line1>,<line2>call vim_ai#AIRun({}, "/vimcmd")
