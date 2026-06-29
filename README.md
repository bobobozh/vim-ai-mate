# Vim-AI

VimAI 是一个强大的 Vim 插件，将 AI 能力直接集成到编辑器中。支持文本补全、代码编辑和交互式对话。

## 特性

- **文本补全**: 使用 AI 自动补全文本或代码
- **文本编辑**: 基于指令编辑和优化现有文本或代码
- **AI 对话**: 在独立窗口中与 AI 进行交互式对话
- **文件包含**: 在对话中包含其他文件内容
- **角色系统**: 使用预定义角色完成不同任务
- **集中配置**: 统一的配置管理，简单易用

## 安装

### 依赖

- Vim 7.4+ with Python 3 support (`:echo has('python3')` should return 1)
- OpenAI API key (或兼容 API 服务)

### 使用插件管理器

推荐使用 Vundle、Pathogen 或 Vim-Plug 安装。在 vimrc 中添加:

```vim
Plug 'bobobocode/VimAI'
```

## 快速开始

### 1. 配置 API Key

在 vimrc 中设置或创建 `~/.config/openai.token` 文件:

```
your-api-key-here
```

### 2. 统一配置

所有配置通过 `g:vim_ai` 集中管理:

```vim
let g:vim_ai = {
\  'api': {
\    'model': 'gpt-4o',
\    'endpoint_url': 'https://api.openai.com/v1/chat/completions',
\    'temperature': 0.7,
\  },
\  'chat': {
\    'window': {
\      'preset': 'right',
\    },
\  },
\}
```

## 命令

| 命令 | 描述 |
|------|------|
| `:AI` | 对当前行/选区进行 AI 补全 |
| `:AI /role` | 使用角色 (如 `/explain`, `/grammar`) |
| `:AIChat` | 打开或继续 AI 对话 |
| `:AINew` | 新建对话 (可指定窗口: `tab`, `bottom`) |
| `:AIRedo` | 重做上次命令 |
| `:AISet` | 显示当前配置 |

### 使用示例

```vim
" 补全当前行
:AI

" 解释选区代码
:'<,'>AI /explain

" 修复语法错误
:AI /grammar

" 重构代码
:AI /refactor

" 打开对话
:AIChat

" 带初始消息打开对话
:AIChat 分析这段代码

" 新标签页打开对话
:AINew tab
```

## 角色系统

预定义角色可通过 `/rolename` 访问:

| 角色 | 描述 |
|------|------|
| `/explain` | 解释代码 |
| `/refactor` | 重构代码 |
| `/test` | 生成单元测试 |
| `/grammar` | 修复语法错误 |
| `/translate` | 翻译为英文 |
| `/chinese` | 改进中文表达 |
| `/review` | 代码审查 |
| `/debug` | 调试代码 |
| `/professional` | 专业表达优化 |
| `/commit` | 生成 git 提交信息 |

### 自定义角色

在 `roles.ini` 中添加自定义角色:

```ini
[myrole]
prompt = Your custom prompt here
options.temperature = 0.5
```

## 窗口预设

| 预设 | 描述 |
|------|------|
| `right` | 右侧 75% 宽度窗口 (默认) |
| `left` | 左侧 50% 宽度窗口 |
| `top` | 顶部窗口 |
| `bottom` | 底部窗口 |
| `tab` | 新标签页 |
| `float` | 浮动窗口 |

## 调试

```vim
let g:vim_ai = {
\  'debug': {
\    'enabled': 1,
\    'log_file': '/tmp/vim_ai_debug.log',
\  },
\}
```

## 向后兼容

旧版变量仍然兼容:

```vim
let g:llm = 'gpt-4'
let g:ai_endpoint_url = 'https://api.openai.com/v1/chat/completions'
```
