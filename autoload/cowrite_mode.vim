function! cowrite_mode#code() range
    let question = "Write code (only code) for these: "
    let question = ask_with#selected(question)
    call chat#on('current', question)
endfunction


function! cowrite_mode#func() range
    let question = "Write functions (only code) to implement the comment: "
    let question = ask_with#selected(question)
    call chat#on('current', question)
endfunction


function! cowrite_mode#test() range
    let question = "Write unit tests (only code) to implement the comment: "
    let question = ask_with#selected(question)
    call chat#on('current', question)
endfunction
