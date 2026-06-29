import vim
import datetime
import glob
import os
import json
import socket
import re
import urllib.error
from urllib.error import URLError, HTTPError
import traceback
import configparser
from openai import OpenAI

# =============================================================================
# 调试支持
# =============================================================================

def get_debug_config():
    return {
        'enabled': vim.eval("g:vim_ai_debug") == "1",
        'log_file': vim.eval("g:vim_ai_debug_log_file"),
    }

def print_debug(text, *args):
    cfg = get_debug_config()
    if not cfg['enabled']:
        return
    with open(cfg['log_file'], "a") as f:
        f.write(f"[{datetime.datetime.now()}] " + text.format(*args) + "\n")

# =============================================================================
# API Key 管理
# =============================================================================

def load_api_key():
    config_file_path = os.path.expanduser(vim.eval("g:vim_ai_token_file_path"))
    api_key = os.environ.get("AI_API_KEY", "")

    try:
        with open(config_file_path, 'r') as f:
            api_key = f.read().strip()
    except Exception:
        pass

    if not api_key:
        raise KnownError("Missing OpenAI API key")

    # 支持 "api_key,org_id" 格式
    elements = api_key.split(",")
    return elements[0].strip(), elements[1].strip() if len(elements) > 1 else None

# =============================================================================
# 自定义异常
# =============================================================================

class KnownError(Exception):
    pass

# =============================================================================
# 配置处理
# =============================================================================

def normalize_config(config):
    """标准化配置格式"""
    normalized = dict(config)
    if 'initial_prompt' in config and isinstance(config['initial_prompt'], str):
        normalized['initial_prompt'] = normalized['initial_prompt'].split('\n')
    return normalized

def get_api_config(config):
    """从配置中提取 API 相关参数"""
    api_section = config.get('api', config)
    return {
        'model': api_section.get('model', 'gpt-4o'),
        'endpoint_url': api_section.get('endpoint_url', 'https://api.openai.com/v1/chat/completions'),
        'temperature': float(api_section.get('temperature', 0.7)),
        'top_p': float(api_section.get('top_p', 0.8)),
        'max_tokens': int(api_section.get('max_tokens', 0)),
        'timeout': float(api_section.get('timeout', 20)),
    }

def get_http_config(config):
    """从配置中提取 HTTP 相关参数"""
    api_section = config.get('api', config)
    return {
        'timeout': float(api_section.get('timeout', 20)),
        'enable_auth': True,
    }

# =============================================================================
# OpenAI 请求
# =============================================================================

OPENAI_RESP_DONE = '[DONE]'

def openai_request(url, data, options):
    """发送 OpenAI 请求，支持流式响应"""
    print_debug('url: {}\ndata: {}\noptions: {}', url, data, options)

    api_key, _ = load_api_key()

    client = OpenAI(
        api_key=api_key,
        base_url=options['endpoint_url'],
        timeout=int(options['timeout'])
    )

    completion = client.chat.completions.create(
        model=options['model'],
        temperature=float(options['temperature']),
        top_p=float(options['top_p']),
        messages=data['messages'],
        stream=True,
        stream_options={"include_usage": False}
    )

    for chunk in completion:
        yield json.loads(chunk.model_dump_json())

# =============================================================================
# 聊天消息解析
# =============================================================================

def parse_chat_messages(chat_content):
    """解析聊天格式的消息"""
    lines = chat_content.splitlines()
    messages = []

    for line in lines:
        if line.startswith(">>> system"):
            messages.append({"role": "system", "content": ""})
            continue
        if line.startswith(">>> user"):
            messages.append({"role": "user", "content": ""})
            continue
        if line.startswith(">>> include"):
            messages.append({"role": "include", "content": ""})
            continue
        if line.startswith("<<< assistant"):
            messages.append({"role": "assistant", "content": ""})
            continue
        if not messages:
            continue
        messages[-1]["content"] += "\n" + line

    # 处理消息内容
    result = []
    for msg in messages:
        msg["content"] = msg["content"].strip()

        if msg["role"] == "include":
            msg = handle_include_directive(msg)
            if msg is None:
                continue

        result.append(msg)

    return result

def handle_include_directive(msg):
    """处理 include 指令"""
    msg["role"] = "user"
    paths = msg["content"].split("\n")
    msg["content"] = ""

    pwd = vim.eval("getcwd()")
    for i in range(len(paths)):
        path = os.path.expanduser(paths[i])
        if not os.path.isabs(path):
            path = os.path.join(pwd, path)

        if '**' in path:
            paths.extend(glob.glob(path, recursive=True))
            paths[i] = None
            continue

        paths[i] = path

    for path in paths:
        if path is None:
            continue
        if os.path.isdir(path):
            continue

        try:
            with open(path, "r") as f:
                msg["content"] += f"\n\n==> {path} <==\n" + f.read()
        except UnicodeDecodeError:
            msg["content"] += "\n\n" + f"==> {path} <==\nBinary file, cannot display"

    return msg

def parse_chat_header_options():
    """解析聊天窗口头部的 [chat-options] 配置"""
    try:
        options = {}
        lines = vim.eval('getline(1, "$")')
        if '[chat-options]' not in lines:
            return options

        options_index = lines.index('[chat-options]')
        for line in lines[options_index + 1:]:
            if line.startswith('#'):
                continue
            if line == '':
                break
            key, value = line.strip().split('=')
            if key == 'initial_prompt':
                value = value.split('\\n')
            options[key] = value
        return options
    except Exception:
        raise Exception("Invalid [chat-options]")

# =============================================================================
# Vim 交互辅助
# =============================================================================

def vim_break_undo_sequence():
    """中断撤销序列"""
    vim.command("let &ul=&ul")

def need_insert_before_cursor(is_selection):
    """判断是否需要在光标前插入"""
    if not is_selection:
        return False
    pos = vim.eval("getpos(\"'<\")[1:2]")
    if not isinstance(pos, list) or len(pos) != 2:
        raise ValueError("Unexpected getpos value")
    return pos[1] == "1"

def render_text_chunks(chunks, is_selection):
    """渲染流式文本块"""
    generating_text = False
    full_text = ''
    insert_before_cursor = need_insert_before_cursor(is_selection)

    for text in chunks:
        if not text.strip() and not generating_text:
            continue
        generating_text = True

        if insert_before_cursor:
            vim.command("normal! i" + text)
            insert_before_cursor = False
        else:
            vim.command("normal! a" + text)
        vim.command("undojoin")
        vim.command("redraw")
        full_text += text

    if not full_text.strip():
        print_info_message('Empty response received. Tip: You can try modifying the prompt and retry.')

def print_info_message(msg):
    """显示信息消息"""
    vim.command("redraw")
    vim.command(r'call feedkeys("\<Esc>")')
    vim.command("echohl ErrorMsg")
    vim.command(f"echomsg '{msg}'")
    vim.command("echohl None")

def clear_echo_message():
    """清除回显消息"""
    vim.command("call feedkeys(':','nx')")

def handle_completion_error(error):
    """处理完成过程中的错误"""
    is_nvim_keyboard_interrupt = "Keyboard interrupt" in str(error)

    if isinstance(error, KeyboardInterrupt) or is_nvim_keyboard_interrupt:
        print_info_message("Completion cancelled...")
    elif isinstance(error, URLError) and isinstance(error.reason, socket.timeout):
        print_info_message("Request timeout...")
    elif isinstance(error, HTTPError):
        status_code = error.getcode()
        msg = f"OpenAI: HTTPError {status_code}"
        if status_code == 401:
            msg += ' (Hint: verify that your API key is valid)'
        elif status_code == 404:
            msg += ' (Hint: verify that you have access to the OpenAI API)'
        elif status_code == 429:
            msg += ' (Hint: verify that your billing plan is "Pay as you go")'
        print_info_message(msg)
    elif isinstance(error, KnownError):
        print_info_message(str(error))
    else:
        raise error

# =============================================================================
# 角色配置
# =============================================================================

def enhance_roles_with_custom_function(roles):
    """通过自定义函数增强角色配置"""
    if vim.eval("exists('g:vim_ai_roles_config_function')") == '1':
        roles_config_function = vim.eval("g:vim_ai_roles_config_function")
        if not vim.eval("exists('*" + roles_config_function + "')"):
            raise Exception(f"Role config function does not exist: {roles_config_function}")
        roles.update(vim.eval(roles_config_function + "()"))

def load_role_config(role):
    """加载指定角色的配置"""
    roles_config_path = os.path.expanduser(vim.eval("g:vim_ai_roles_config_file"))
    if not os.path.exists(roles_config_path):
        raise Exception(f"Role config file does not exist: {roles_config_path}")

    roles = configparser.ConfigParser()
    roles.read(roles_config_path)
    enhance_roles_with_custom_function(roles)

    if role not in roles:
        raise Exception(f"Role `{role}` not found")

    options = roles[f"{role}.options"] if f"{role}.options" in roles else {}
    options_complete = roles[f"{role}.options-complete"] if f"{role}.options-complete" in roles else {}
    options_chat = roles[f"{role}.options-chat"] if f"{role}.options-chat" in roles else {}

    return {
        'role': dict(roles[role]),
        'options': {
            'options_default': dict(options),
            'options_complete': dict(options_complete),
            'options_chat': dict(options_chat),
        },
    }

empty_role_options = {
    'options_default': {},
    'options_complete': {},
    'options_chat': {},
}

def parse_prompt_and_role(raw_prompt):
    """解析提示词和角色"""
    prompt = raw_prompt.strip()
    role = re.split(' |:', prompt)[0]

    if not role.startswith('/'):
        return (prompt, empty_role_options)

    prompt = prompt[len(role):].strip()
    role = role[1:]

    config = load_role_config(role)
    if 'prompt' in config['role'] and config['role']['prompt']:
        delim = '' if prompt.startswith(':') else ':\n'
        prompt = config['role']['prompt'] + delim + prompt

    return (prompt, config['options'])
