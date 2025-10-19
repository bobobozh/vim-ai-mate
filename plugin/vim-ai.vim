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

let g:vim_ai_chat = {
\  "options": {
\    "model": g:llm,
\    "endpoint_url": g:ai_endpoint_url,
\    "top_p": 0.8,
\    "temperature": 0.8,
\  },
\}

let g:vim_ai_complete = g:vim_ai_chat
let g:vim_ai_edit = g:vim_ai_chat

let g:vim_ai_debug = "1"
let g:vim_ai_debug_log_file = "/Users/bobobo/Projects/workbench/logs/VimAI.log"


" Whereas AI and AIEdit default to passing the current line as range
" AIChat defaults to passing nothing which is achieved by -range=0 and passing
" <count> as described at https://stackoverflow.com/a/20133772
command! -range   -nargs=? -complete=customlist,vim_ai#RoleCompletion AI        <line1>,<line2>call vim_ai#AIRun({}, <q-args>)


command! -nargs=?                                                     AINewChat                call vim_ai#AINewChatRun(<f-args>)
command!                                                              AIRedo                   call vim_ai#AIRedoRun()


command! -range=0 -nargs=? -complete=customlist,vim_ai#RoleCompletion AIChat    <line1>,<line2>call vim_ai#AIChatRun(<count>, {}, <q-args>)
command! -range=0 -nargs=? -complete=customlist,vim_ai#RoleCompletion AIp    <line1>,<line2>call vim_ai#AIChatRun(<count>, {}, "Explain")
command! -range=0 -nargs=? -complete=customlist,vim_ai#RoleCompletion AIut    <line1>,<line2>call vim_ai#AIChatRun(<count>, {}, 
            \"Write functional unit tests (just give the program without other content) for")


command! -range   -nargs=? -complete=customlist,vim_ai#RoleCompletion AIEdit    <line1>,<line2>call vim_ai#AIEditRun({}, <q-args>)

command! -range   -nargs=? -complete=customlist,vim_ai#RoleCompletion AIe    <line1>,<line2>call vim_ai#AIEditRun({}, 
            \"Improve English expression.And just give the new expression without other content.")
command! -range   -nargs=? -complete=customlist,vim_ai#RoleCompletion AIen    <line1>,<line2>call vim_ai#AIEditRun({}, 
            \"Improve English expression. Provide the revised version, teach the hard words.")

command! -range   -nargs=? -complete=customlist,vim_ai#RoleCompletion AIw    <line1>,<line2>call vim_ai#AIEditRun({}, 
            \"Write code to complete the comments in the content.And just give the program without other content.")
command! -range   -nargs=? -complete=customlist,vim_ai#RoleCompletion AIr    <line1>,<line2>call vim_ai#AIEditRun({}, 
            \"Correct this content.Just make it right.Do not improve it.Just give the content to replace it without anything else.")
