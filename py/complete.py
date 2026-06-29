import vim

# 加载公共模块
plugin_root = vim.eval("s:plugin_root")
vim.command(f"py3file {plugin_root}/py/utils.py")

config = normalize_config(vim.eval("l:config"))
api_options = get_api_config(config)

prompt, role_options = parse_prompt_and_role(vim.eval("l:prompt"))
config_options = {
    **api_options,
    **role_options.get('options_default', {}),
    **role_options.get('options_complete', {}),
}

is_selection = vim.eval("l:is_selection") == "1"

def chat_engine(prompt_text):
    """使用 chat API 进行补全"""
    messages = [
        {'role': 'system', 'content': 'You are a helpful assistant.'},
        {'role': 'user', 'content': prompt_text},
    ]
    request = {
        'stream': True,
        'messages': messages,
    }
    print_debug("[engine-chat] request: {}", request)
    response = openai_request(config_options['endpoint_url'], request, config_options)

    def map_chunk(resp):
        print_debug("[engine-chat] response: {}", resp)
        return resp['choices'][0]['delta'].get('content', '')

    return map(map_chunk, response)

try:
    if prompt:
        print('Completing...')
        vim.command("redraw")
        text_chunks = chat_engine(prompt)
        render_text_chunks(text_chunks, is_selection)
        clear_echo_message()

except BaseException as error:
    handle_completion_error(error)
    print_debug("[complete] error: {}", traceback.format_exc())
