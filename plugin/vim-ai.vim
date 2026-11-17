" =============================================================================
" Vim-AI 插件入口（纯 Vimscript 版本）
" 基于 curl + job 的异步流式请求，全异步不阻塞 Vim 编辑
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

command! -range   -nargs=? Aen    <line1>,<line2>call vim_ai#AIRun({}, "/english")
command! -range   -nargs=? Aten   <line1>,<line2>call vim_ai#AIRun({}, "/english-tutor")
command! -range   -nargs=? Apro   <line1>,<line2>call vim_ai#AIRun({}, "/professional")
command! -range   -nargs=? Aw     <line1>,<line2>call vim_ai#AIRun({}, "/chinese")
command! -range   -nargs=? AIv    <line1>,<line2>call vim_ai#AIRun({}, "/vimcmd")

" =============================================================================
" 提示词工程命令
" =============================================================================

command! -nargs=0 AIPrompt       call vim_ai_prompt#StartPrompt()
command! -nargs=0 AIPromptDraft  call vim_ai_prompt#StartDraft()
command! -nargs=0 AIPromptRefine call vim_ai_prompt#RefinePrompt()
command! -nargs=0 AIPromptIterate call vim_ai_prompt#IteratePrompt()
command! -nargs=0 AIPromptSave   call vim_ai_prompt#SavePrompt()
command! -nargs=0 AIPromptLoad   call vim_ai_prompt#LoadPrompt()
command! -nargs=0 AIPromptList   call vim_ai_prompt#ListTemplates()

" =============================================================================
" 英语写作辅助命令
" =============================================================================

command! -range -nargs=? AECheck      <line1>,<line2>call vim_ai_english#Check(<count>, <q-args>)
command! AECheckClear                  call vim_ai_english#CheckClear()
command! -nargs=? AEWrite              call vim_ai_english#WriteStart(<q-args>)
command! -range AETutor                <line1>,<line2>call vim_ai_english#Tutor()
command! -nargs=? AESay                call vim_ai_english#Say(<q-args>)
command! -range AEPhonetic             <line1>,<line2>call vim_ai_english#Phonetic()
command! -range AESave                 <line1>,<line2>call vim_ai_english#SaveExpression()
command! -nargs=? AESearch             call vim_ai_english#SearchExpression(<q-args>)
command! AEPaste                       call vim_ai_english#PasteExpression()

" =============================================================================
" 陪伴编写（自动异步，不阻塞）
" =============================================================================

command! -nargs=? AICompanionOn   call vim_ai_companion#Enable(<q-args>)
command! AICompanionOff           call vim_ai_companion#Disable()
command! AICompanionStatus        call vim_ai_companion#Status()

" =============================================================================
" 初始化新模块（autoload 通过引用自动加载，这里确保 store/tools 就绪）
" =============================================================================

" vim_ai_store — 确保存储目录存在
silent! call vim_ai_store#Path('conversations')
silent! call vim_ai_store#Path('prompts')
silent! call vim_ai_store#Path('expressions')

" vim_ai_tools — 注册内置工具（在 autoload 里自动执行）
" call vim_ai_tools#Init()  -- 已在 vim_ai_tools.vim 末尾自动调用

" vim_ai_companion — 默认关闭，手动 :AICompanionOn 开启
" （在 autoload 模块内部有自己的 autocmd 管理）
