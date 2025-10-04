"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Talk Mode:
"   Open a split window(AI.chat) to talk to AI(ChatGPT)
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""

let g:AI_OUTPUT_SPLIT = '.AI.chat'

" Send a question to ChatGPT
command -nargs=+ AI call chat_mode#chat(<q-args>)
" Chat with the selected lines
command -range=% AIwith call chat_mode#chat_with(<q-args>)
" Review the selected lines
command -range=% AIreview call chat_mode#review()

command Acl call chat_mode#close()


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Cowrite Mode:
"   Write answer into the file
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Write code for the selected content
command -range=% Ac call cowrite_mode#code()
" Write function for the selected comment
command -range=% Acfunc call cowrite_mode#func()
" Write unittest for the selected comment
command -range=% Actest call cowrite_mode#test()


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Pair Mode:
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
