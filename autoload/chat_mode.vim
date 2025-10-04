function! chat_mode#chat(question)
    call chat#on(g:AI_OUTPUT_SPLIT, a:question)
endfunction


function! chat_mode#chat_with(question) range
    let question = ask_with#selected(a:question)
    call chat#on(g:AI_OUTPUT_SPLIT, question)
endfunction


function! chat_mode#review() range
    let question = "Review code as follows, improve it, and tell me why: "
    let question = ask_with#selected(question)
    call chat#on(g:AI_OUTPUT_SPLIT, question)
endfunction


function! chat_mode#close()
    call chat#close(g:AI_OUTPUT_SPLIT)
endfunction
