import vim

# 加载公共模块
plugin_root = vim.eval("s:plugin_root")
vim.command(f"py3file {plugin_root}/py/utils.py")

prompt, role_options = parse_prompt_and_role(vim.eval("l:prompt"))
config = normalize_config(vim.eval("l:config"))
api_options = get_api_config(config)

# 合并角色特定配置
config_options = {
    **api_options,
    **role_options.get('options_default', {}),
    **role_options.get('options_chat', {}),
}

chat_options = parse_chat_header_options()
options = {**config_options, **chat_options}

initial_prompt = '\n'.join(options.get('initial_prompt', []))
initial_messages = parse_chat_messages(initial_prompt) if initial_prompt else []

chat_content = vim.eval('trim(join(getline(1, "$"), "\n"))')
chat_messages = parse_chat_messages(chat_content)
is_selection = vim.eval("l:is_selection") == "1"

messages = initial_messages + chat_messages

try:
    if messages[-1]["content"].strip():
        vim.command("normal! Go\n<<< assistant\n\n")
        vim.command("redraw")

        print('Answering...')
        vim.command("redraw")

        request = {
            'stream': True,
            'messages': messages,
        }

        print_debug("[chat] request: {}", request)
        response = openai_request(options['endpoint_url'], request, options)

        def map_chunk(resp):
            print_debug("[chat] response: {}", resp)
            content = resp['choices'][0]['delta'].get('content', '')
            return content

        text_chunks = map(map_chunk, response)
        render_text_chunks(text_chunks, is_selection)

        vim.command("normal! a\n\n>>> user\n\n")
        vim.command("redraw")
        clear_echo_message()

except BaseException as error:
    handle_completion_error(error)
    print_debug("[chat] error: {}", traceback.format_exc())
