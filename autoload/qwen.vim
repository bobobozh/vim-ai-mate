function! qwen#chat(input)
    let l:api_key = g:qwen_api_key
    let l:url = "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation"
    let l:prompt = a:input

    let l:headers = {"Authorization": "Bearer " . l:api_key, "Content-Type": "application/json"}
    let l:payload = '{"model": "qwen-turbo", "input":{ "messages":[ { "role": "user", "content": "' . l:prompt . '" } ] }, "parameters": { } }'

    let response = system('curl --connect-timeout 10 -m 60 -s -H "Content-Type: application/json" -H "Authorization: Bearer ' . l:api_key . '" -d ' . shellescape(l:payload) . ' ' . l:url)

    if v:shell_error
        return "Error"
    else
        let json_response = json_decode(response)
        if has_key(json_response, 'output')
            let text_completion = json_response['output']['text']
            return text_completion
        elseif has_key(json_response, 'error')
            let error_msg = json_response['error']['message']
            return error_msg
        else
            return response
        endif
    endif
endfunction
