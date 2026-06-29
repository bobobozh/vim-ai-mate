# Vim-AI

Vim-AI 是一个强大的 Vim 插件，将 AI 能力直接集成到编辑器中。支持文本补全、代码编辑和交互式对话，默认使用阿里云通义千问（DashScope）。

> **pure-vim 分支**: 纯 Vimscript 实现，零 Python 依赖，基于 `curl` + `job` 的异步流式请求。

## 特性

- **纯 Vimscript**: 零 Python 依赖，只需系统有 `curl` 即可
- **文本补全**: 使用 AI 自动补全文本或代码
- **文本编辑**: 基于指令编辑和优化现有文本或代码
- **AI 对话**: 在独立窗口中与 AI 进行交互式对话
- **文件包含**: 在对话中包含其他文件内容（支持 glob 匹配）
- **角色系统**: 20+ 预定义角色，覆盖代码、文本、开发辅助等场景
- **集中配置**: 统一的 `g:vim_ai` 配置，简单易配置
- **多模型兼容**: 支持所有 OpenAI 兼容 API（通义千问、DeepSeek、Kimi 等）

## 安装

### 依赖

- Vim 8.0+ / Neovim（支持 `job` 和 `json_decode`）
- 系统安装 `curl`（macOS / Linux 默认自带）
- DashScope API Key（或其他 OpenAI 兼容服务的 API Key）

### 使用插件管理器

推荐使用 Vim-Plug：

```vim
Plug 'bobobozh/vim-ai-mate'
```

安装后执行 `:PlugInstall`。

## 快速开始

### 1. 配置 API Key

**方式一：文件方式（推荐）**

创建 `~/.config/dashscope.token` 文件，写入你的 API Key：

```
sk-xxxxxxxxxxxxxxxxxxxxxxxx
```

**方式二：环境变量**

```bash
export AI_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxx
```

**方式三：自定义文件路径**

```vim
let g:vim_ai = {
\  'api': {
\    'api_key_file': '~/.config/my-ai-key',
\  },
\}
```

### 2. 开始使用

```vim
" 补全当前行
:AI

" 修复选中代码的语法错误
:'<,'>AI /grammar

" 打开对话窗口
:AIChat
```

## 配置

所有配置通过 `g:vim_ai` 统一管理，以下是完整配置及默认值：

```vim
let g:vim_ai = {
\  'api': {
\    'provider': 'qwen',
\    'model': 'qwen-plus',
\    'endpoint_url': 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
\    'api_key_file': '~/.config/dashscope.token',
\    'timeout': 30,
\    'temperature': 0.7,
\    'top_p': 0.8,
\    'max_tokens': 0,
\  },
\  'chat': {
\    'window': {
\      'preset': 'right',
\      'keep_open': 0,
\    },
\    'ui': {
\      'paste_mode': 1,
\      'code_syntax': 1,
\    },
\  },
\  'edit': {
\    'model': 'qwen-turbo',
\    'temperature': 0.1,
\  },
\  'completion': {
\    'model': 'qwen-turbo',
\    'temperature': 0.1,
\  },
\  'roles': {
\    'config_file': '插件目录/roles.ini',
\  },
\  'debug': {
\    'enabled': 0,
\    'log_file': '/tmp/vim_ai_debug.log',
\  },
\}
```

### 切换到其他模型

#### 通义千问系列

```vim
let g:vim_ai = {
\  'api': {
\    'model': 'qwen-max',      " 或 qwen-turbo, qwen-plus, qwen-long
\  },
\}
```

#### OpenAI

```vim
let g:vim_ai = {
\  'api': {
\    'provider': 'openai',
\    'model': 'gpt-4o',
\    'endpoint_url': 'https://api.openai.com/v1/chat/completions',
\    'api_key_file': '~/.config/openai.token',
\  },
\}
```

#### DeepSeek

```vim
let g:vim_ai = {
\  'api': {
\    'model': 'deepseek-chat',
\    'endpoint_url': 'https://api.deepseek.com/chat/completions',
\    'api_key_file': '~/.config/deepseek.token',
\  },
\}
```

## 命令

### 核心命令

| 命令 | 描述 |
|------|------|
| `:AI` | 对当前行/选区进行 AI 补全 |
| `:AIChat` | 打开或继续 AI 对话 |
| `:AINew` | 新建对话（可指定窗口位置） |
| `:AIRedo` | 重做上次 AI 命令 |
| `:AISet` | 显示当前配置 |

### 简写命令

| 命令 | 对应角色 | 描述 |
|------|---------|------|
| `AIp` | `/explain` | 解释代码 |
| `AIut` | `/test` | 生成单元测试 |
| `AIw` | `/refactor` | 重构代码 |
| `AIr` | `/grammar` | 修复语法错误 |
| `Aen` | `/english` | 改进英语表达 |
| `Aten` | `/english-tutor` | 英语老师模式（带中文解释） |
| `Apro` | `/professional` | 专业表达优化 |
| `Aw` | `/chinese` | 改进中文笔记 |

### 使用示例

```vim
" 补全当前行
:AI

" 带提示补全
:AI 写一个 Python 快速排序函数

" 解释选中的代码
:'<,'>AI /explain

" 重构选中的代码
:'<,'>AI /refactor

" 打开对话
:AIChat

" 带初始消息打开对话
:AIChat 解释一下什么是闭包

" 新标签页打开对话
:AINew tab

" 底部打开对话
:AINew bottom
```

## 角色系统

预定义角色通过 `/rolename` 访问，所有角色都可以直接与 `:AI` 或 `:AIChat` 配合使用。

### 代码相关

| 角色 | 描述 |
|------|------|
| `/explain` | 解释代码 |
| `/refactor` | 重构代码 |
| `/test` | 生成单元测试 |
| `/review` | 代码审查 |
| `/debug` | 调试代码并提供修复方案 |
| `/code-review` | 全面的代码评审（质量、bug、性能、安全） |
| `/api-design` | API 设计评审 |
| `/sql` | SQL 查询优化 |
| `/regex` | 正则表达式解释 |

### 文本相关

| 角色 | 描述 |
|------|------|
| `/grammar` | 修复拼写和语法错误 |
| `/translate` | 翻译为英文 |
| `/english` | 改进英语表达 |
| `/english-tutor` | 英语老师模式（带中文解释） |
| `/chinese` | 改进中文笔记和文章 |
| `/summary` | 总结要点 |
| `/professional` | 专业表达优化 |

### 开发辅助

| 角色 | 描述 |
|------|------|
| `/commit` | 生成 git 提交信息（Conventional Commits 格式） |
| `/pr` | 生成 Pull Request 描述 |

### 自定义角色

在 `roles.ini` 中添加自定义角色：

```ini
[myrole]
prompt = Your custom prompt here

[myrole.options]
temperature = 0.5
model = qwen-max
```

也可以通过 Vim 函数动态定义角色：

```vim
function! MyRoles()
  return {
    \ 'myrole': {'prompt': '...'},
    \ 'myrole.options': {'temperature': '0.5'},
    \ }
endfunction
let g:vim_ai_roles_config_function = 'MyRoles'
```

## 对话功能

### 文件包含

在对话中使用 `>>> include` 指令包含文件内容：

```
>>> include
/path/to/file.py
/path/to/dir/**/*.js
```

支持 glob 模式（`**`, `*` 等）。

### 聊天选项

在对话文件开头设置特定参数：

```
[chat-options]
model=qwen-max
temperature=0.5

>>> user
你好
```

## 窗口预设

| 预设 | 描述 |
|------|------|
| `right` | 右侧 75% 宽度窗口（默认） |
| `left` | 左侧 50% 宽度窗口 |
| `top` | 顶部窗口 |
| `bottom` | 底部窗口 |
| `tab` | 新标签页 |
| `float` | 浮动窗口 |

设置默认窗口：

```vim
let g:vim_ai = {
\  'chat': {
\    'window': {
\      'preset': 'bottom',
\    },
\  },
\}
```

## 调试

```vim
let g:vim_ai = {
\  'debug': {
\    'enabled': 1,
\    'log_file': '/tmp/vim_ai_debug.log',
\  },
\}
```

查看日志：

```bash
tail -f /tmp/vim_ai_debug.log
```

## 快捷键建议

```vim
" 补全
nnoremap <leader>a :AI<CR>
xnoremap <leader>a :AI<CR>

" 对话
nnoremap <leader>c :AIChat<CR>
xnoremap <leader>c :AIChat<CR>

" 重做
nnoremap <leader>r :AIRedo<CR>
```

## 向后兼容

旧版配置变量仍然支持：

```vim
let g:llm = 'qwen-max'
let g:ai_endpoint_url = 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions'
```

## License

MIT
