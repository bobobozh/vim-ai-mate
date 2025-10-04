function! InsertAfterSelection(content)
    let end_pos = getpos("'>")
    let line_num = end_pos[1]
    call append(line_num, a:content)
endfunction


function! Chat(question, show_mode='full')
    if a:show_mode == 'full'
        let now = strftime("%H:%M:%S")

        let question_len = len(a:question)
        if question_len > 50
            let show_question = strpart(a:question, 0, 70) . "~~~"
        else
            let show_question = a:question
        endif

        call append(line('$'), "Me: " . show_question)
        call append(line('$'), "AI: ...")
        call cursor(line('$'), 0)
        redraw

        let response = qwen#chat(a:question)
        let respl = split(response, '\n')

        call append(line('$'), '')
        for rp in respl
            call append(line('$'), rp)
        endfor
        call append(line('$'), '')
        call append(line('$'), '-----------------------------------')
        call append(line('$'), '')
        call append(line('$'), '')
        call cursor(line('$'), 0)
        redraw
        write
    else
        let response = qwen#chat(a:question)
        let respl = split(response, '\n')
        for i in range(len(respl) - 1, 0, -1)
            let r = InsertAfterSelection(respl[i])
        endfor
    endif
endfunction


function! chat#on(split_name, question)
    if a:split_name == 'current'
        let ret = Chat(a:question, 'answer')
    else
        let src_win_id = win_getid()

        let chat_win_id = bufwinnr(a:split_name)
        if chat_win_id == -1
            execute "vert rightbelow new " . a:split_name
            vertical resize 70%
            execute "e ++enc=utf-8"
            let g:chat_win_id = win_getid()
        endif

        call win_gotoid(g:chat_win_id)
        let ret = Chat(a:question)
        execute "w"
    endif
endfunction


function! chat#close(split_name)
    let src_win_id = win_getid()
    let chat_win_id = bufwinnr(a:split_name)

    if chat_win_id != -1
        call win_gotoid(g:chat_win_id)
        wincmd q
        call win_gotoid(src_win_id)
    endif
endfunction
