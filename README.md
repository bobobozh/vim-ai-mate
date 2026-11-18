# Vim-AI Mate

> pure-vim 分支：纯 Vimscript 实现，零 Python 依赖，基于 `curl` + `job` 的**全异步**流式请求，不阻塞 Vim 编辑。

Vim-AI Mate 把大模型能力嵌入 Vim 原生工作流，核心优势：

- **零依赖、纯 Vimscript、SSH 远程可用** — 只有 `curl` 就够
- **完全可控的 prompt 构建** — role system 是核心资产
- **与 Vim 原生操作深度融合** — 寄存器、宏、ex command
- **自动上下文感知** — 注入 git diff、filetype、光标附近代码
- **Tool Calling Agent** — AI 可调用 shell、文件操作、vim_eval（带安全沙箱）
- **陪伴编写** — 低频率自动跳出来说句贴心话，不打扰

---

## 特性速览

| 能力 | 说明 |
|------|------|
| AI 补全/编辑/对话 | 异步流式，多模型兼容 |
| **自动上下文注入** | git repo / branch / diff / 改动文件列表 / 光标代码窗口 |
| **英语写作辅助** | `:AECheck` 语法标注、`:AEWrite` 多维度反馈、`:AETutor` 逐句教学、TTS、音标、表达库 |
| **陪伴编写** | `:AICompanionOn` 开启，编辑量积累到阈值即异步生成一句简短话语，不打断写作 |
| **Tool Calling Agent** | AI 主动调用 shell / file_read / file_glob / vim_eval |
| **Token 计费显示** | 每次 Done 后自动显示 `[in:xxx, out:xxx]` |
| **对话持久化** | JSON 格式存到 `~/.vim/ai_store/conversations/` |
| **25+ 角色** | 代码 / 英语（细粒度）/ 开发辅助 |
| **纯 Vimscript** | 零依赖，启动即加载 |

---

## 安装

### 依赖

- Vim 8.0+ / Neovim（支持 `job` 和 `json_decode`）
- 系统 `curl`（macOS / Linux 默认自带）
- API Key：通义千问 / DeepSeek / Kimi / OpenAI 兼容服务

### Vim-Plug

```vim
Plug 'bobobozh/vim-ai-mate'
```

安装后 `:PlugInstall`。

---

## API Key 配置

### 方式一：文件（推荐）

```bash
# 通义千问
echo "sk-xxxxx" > ~/.config/dashscope.token

# DeepSeek
echo "sk-xxxxx" > ~/.config/deepseek.token
```

### 方式二：环境变量

```bash
export AI_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxx
```

### 方式三：自定义路径

```vim
let g:vim_ai = {
\  'api': {
\    'api_key_file': '~/.config/my-ai-key',
\  },
\}
```

---

## 快速开始

```vim
" 补全当前行（异步，不阻塞）
:AI

" 重构选中代码
:'<,'>AI /refactor

" 打开对话窗口
:AIChat

" 检查英语语法（高亮标注问题行）
:'<,'>AECheck

" 英语写作多维度反馈
:AEWrite

" 英语逐句教学讲解（选中文本后）
:'<,'>AETutor

" 调用系统 TTS 朗读选中词
:AESay

" 开启陪伴编写（几分钟一次异步贴心话）
:AICompanionOn
```

---

## 完整配置

```vim
let g:vim_ai = {
\  " API 配置
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

\  " 自动上下文注入（git、光标代码窗口）
\  'context': {
\    'enabled': 1,
\    'git': {
\      'enabled': 1,
\      'max_diff_chars': 4000,
\      'include_status': 1,
\    },
\    'cursor': {
\      'enabled': 1,
\      'window_lines': 20,
\    },
\  },

\  " 对话窗口
\  'chat': {
\    'window': {
\      'preset': 'right',   " right | left | top | bottom | tab | float
\      'keep_open': 0,
\    },
\    'ui': {
\      'paste_mode': 1,
\      'code_syntax': 1,
\    },
\  },

\  " AI 编辑专用（低温度、轻量模型）
\  'edit': {
\    'model': 'qwen-turbo',
\    'temperature': 0.1,
\  },

\  " AI 补全专用
\  'completion': {
\    'model': 'qwen-turbo',
\    'temperature': 0.1,
\  },

\  " 角色文件
\  'roles': {
\    'config_file': '插件目录/roles.ini',
\  },

\  " 调试
\  'debug': {
\    'enabled': 0,
\    'log_file': '/tmp/vim_ai_debug.log',
\  },
\}
```

### 切换模型

```vim
" DeepSeek
let g:vim_ai = {
\  'api': {
\    'model': 'deepseek-chat',
\    'endpoint_url': 'https://api.deepseek.com/chat/completions',
\    'api_key_file': '~/.config/deepseek.token',
\  },
\}

" OpenAI
let g:vim_ai = {
\  'api': {
\    'provider': 'openai',
\    'model': 'gpt-4o',
\    'endpoint_url': 'https://api.openai.com/v1/chat/completions',
\    'api_key_file': '~/.config/openai.token',
\  },
\}
```

### 关闭自动上下文注入

```vim
let g:vim_ai = {
\  'context': {'enabled': 0},
\}
```

---

## 命令总览

### 核心命令

| 命令 | 描述 |
|------|------|
| `:AI` | 对当前行/选区进行 AI 补全或编辑（异步） |
| `:AIChat` | 打开或继续 AI 对话窗口 |
| `:AINew` | 新建对话（可指定窗口位置：right/left/top/bottom/tab） |
| `:AIRedo` | 重做上次 AI 命令 |
| `:AISet` | 显示当前配置 |

### 英语写作辅助 ⭐

| 命令 | 描述 |
|------|------|
| `:AECheck [:range]` | 检查英语文本，用不同颜色高亮问题行（error / warning / suggestion） |
| `:AECheckClear` | 清除所有标注 |
| `:AEWrite` | 多维度写作分析（评分 / 语法 / 地道性 / 改写版本），流式显示在侧边栏 |
| `:AETutor [:range]` | 英语逐句教学讲解（原句/句意/语言点/更地道/扩展），流式侧边栏 |
| `:AESay [text]` | macOS TTS 朗读（默认读光标下的词） |
| `:AEPhonetic [:range]` | 获取音标、发音要点、例句 |
| `:AESave [:range]` | 把选中的好表达存入表达库 |
| `:AESearch [query]` | 模糊检索表达库，选中后可插入到 buffer |

### 陪伴编写 ⭐

| 命令 | 描述 |
|------|------|
| `:AICompanionOn [cooldown] [threshold]` | 开启（默认冷却 5 分钟，编辑量阈值 60） |
| `:AICompanionOff` | 关闭 |
| `:AICompanionStatus` | 查看状态（冷却、已积累编辑量） |

**触发机制（不打断写作节奏）：**

```
你持续输入 → TextChangedI/TextChanged 只做轻量累加（changedtick 差值）
        ↓
每 10 秒定时器检查：编辑量 ≥ 阈值 + 冷却期已过 + 最近 2 分钟内仍有输入
        ↓
异步调 AI（携带文件/后缀/净行变化/时段/连续强度/上次开口间隔/光标附近内容）
        ↓
从启发式 / 反馈式 / 提醒式中选一种，生成 1 句（20-35 字）
        ↓
写入 AIChat 对话窗口 + 消息区（echomsg）
```

不需要停下来等待——只要你一直在写，编辑量攒够就会触发；输入路径上没有任何网络或磁盘 IO。

**参数说明：**

```vim
:AICompanionOn              " 冷却 5 分钟，阈值 60
:AICompanionOn 10           " 冷却 10 分钟
:AICompanionOn 5 120        " 冷却 5 分钟，编辑量阈值 120（更少打扰）
```

**三种陪伴姿态（AI 每次只挑最贴合一种，只说一句）：**

| 姿态 | 作用 | 例子 |
|------|------|------|
| A 启发式 | 提一个小问题或换个视角，帮你自己往下想 | "这段和上面的错误处理是不是有点重复？" |
| B 反馈式 | 指出刚写内容里具体的一处，说它好在哪或值得再看一眼 | "这个边界条件兜得挺细" |
| C 提醒式 | 节奏/身体/上下文切换的简短提醒，有依据 | "这段已经改了三轮，先跑一遍看看" |

**设计原则：**
- 节奏优先：触发判断放在定时器里，不占用输入路径
- 频率低：冷却期默认 5 分钟，阈值可调
- 有实效：启发 / 反馈 / 提醒三选一，必须落在光标附近的真实内容上
- 不矫情：不说"加油"、"保持专注"、"朋友"这种空泛话，不煽情
- 有依据：参考文件类型、内容、净行变化（在展开写还是在精简）、时段、连续强度、上次开口间隔
- 静默失败：API 出错不提示，不打断编码

**不触发的场景：**
- scratch buffer、只读 buffer、aichat 对话窗口
- 大文件（> 1500 行）
- 编辑量未达阈值；或最近 2 分钟无输入（离开后回来不会补发）

### 提示词工程

| 命令 | 描述 |
|------|------|
| `:AIPrompt` / `:AIPromptDraft` | 输入提示词草稿 |
| `:AIPromptRefine` | AI 异步协助细化提示词 |
| `:AIPromptIterate` | 基于执行结果反馈，AI 异步迭代优化提示词 |
| `:AIPromptSave` / `:AIPromptLoad` | 保存/加载提示词到 `~/.vim/ai_store/prompts/` |
| `:AIPromptList` | 列出内置提示词模板 |

### 简写命令（角色快捷）

| 命令 | 角色 | 描述 |
|------|------|------|
| `AIp` | `/explain` | 解释代码 |
| `AIut` | `/test` | 生成单元测试 |
| `AIw` | `/refactor` | 重构代码 |
| `Aen` | `/english` | 改进英语表达 |
| `Aten` | `/english-tutor` | 英语老师模式（带中文解释） |
| `Apro` | `/professional` | 专业表达优化 |
| `Aw` | `/chinese` | 改进中文笔记 |
| `AIv` | `/vimcmd` | 自然语言转 Vim ex 命令 |

---

## 角色系统

通过 `/rolename` 访问，配合 `:AI` 或 `:AIChat` 使用。

### 代码相关

| 角色 | 描述 |
|------|------|
| `/explain` | 解释代码（含逻辑、边界、改进点） |
| `/refactor` | 重构代码 + 重构理由 |
| `/test` | 生成单元测试 |
| `/review` | 代码审查 |
| `/debug` | 调试 + 修复方案 |
| `/code-review` | 全面评审（质量、bug、性能、安全） |
| `/api-design` | API 设计评审 |
| `/sql` | SQL 优化 |
| `/regex` | 正则解释 |

### 英语写作（细粒度）

| 角色 | 描述 |
|------|------|
| `/grammar` | 修复拼写语法 |
| `/english` | 地道化改写 |
| `/english-tutor` | 英语老师（带中文解释） |
| `/business-email` | 商务邮件风格 |
| `/academic` | 学术写作风格 |
| `/casual` | 口语化改写 |
| `/concise` | 压缩到 50% 长度 |
| `/business-writing` | 商务写作优化（去 fluff） |
| `/vocab-boost` | 替换高级词汇 |

### 中文/通用

| 角色 | 描述 |
|------|------|
| `/chinese` | 改进中文笔记（结构清晰、表达完整） |
| `/translate` | 翻译为英文 |
| `/summary` | 总结要点 |
| `/professional` | 软件开发专业表达优化 |

### 开发辅助

| 角色 | 描述 |
|------|------|
| `/commit` | 生成 Conventional Commits 格式提交信息 |
| `/pr` | 生成 Pull Request 描述 |
| `/vimcmd` | 自然语言 → Vim ex 命令 |

### 自定义角色

在 `roles.ini` 中添加：

```ini
[myrole]
prompt = Your custom prompt here

[myrole.options]
temperature = 0.5
model = qwen-max
```

或通过 Vim 函数动态定义：

```vim
function! MyRoles()
  return {
    \ 'myrole': {'prompt': '...'},
    \ 'myrole.options': {'temperature': '0.5'},
    \ }
endfunction
let g:vim_ai_roles_config_function = 'MyRoles'
```

---

## 自动上下文注入

默认开启（可通过 `g:vim_ai.context.enabled = 0` 关闭）。每次 AI 请求时，自动收集：

- **当前文件** — 路径、语言、总行数、光标位置
- **Git 仓库** — repo 根目录、当前分支、`git status` 改动文件列表（前 10 个）
- **Git Diff** — 当前文件的 staged + unstaged diff（截断到 4000 字符）
- **光标窗口** — 光标前后各 20 行代码，用 `>` 标记光标行

这些信息以 system message 的形式插入到对话历史最前面，让 AI 精准理解你的开发场景。

---

## Tool Calling Agent

通过内置工具，AI 可以在对话中主动调用 shell、文件操作等能力。

### 内置工具

| 工具 | 描述 |
|------|------|
| `shell_execute` | 执行 shell 命令，返回 stdout |
| `file_read` | 读取文件内容（支持行范围） |
| `file_glob` | Glob 匹配文件 |
| `vim_eval` | 求值 Vimscript 表达式 |

### 安全机制

- **危险命令黑名单** — `rm -rf /`、`curl \| sh`、`mkfs`、`dd` 写块设备等自动拦截
- **审计日志** — 所有 shell 执行记录到 `~/.vim/ai_store/audit/`
- **超时熔断** — 单次 agent 最多 5 轮工具调用

### 注册自定义工具

```vim
let g:vim_ai_custom_tools = [
\  {
\    'type': 'function',
\    'function': {
\      'name': 'my_tool',
\      'description': 'My custom tool',
\      'parameters': {
\        'type': 'object',
\        'properties': {
\          'param': {'type': 'string', 'description': '...'},
\        },
\        'required': ['param'],
\      },
\    },
\  },
\]
```

---

## 英语写作辅助详解

### `:AECheck` — 语法标注

```vim
:'<,'>AECheck
```

AI 分析选中的英语文本，返回 JSON 格式的问题列表。插件用 Vim `matchadd` 按严重程度着色：

| 严重程度 | 高亮组 |
|---------|--------|
| error | ErrorMsg（红色） |
| warning | WarningMsg（黄色） |
| suggestion | Comment（灰色） |

光标放在标注行上按 `<leader>ce` 查看详情（问题描述 + 建议修正）。

### `:AEWrite` — 多维度写作反馈

```vim
:AEWrite           " 分析当前 buffer 的全部英语
:AEWrite 商务场景   " 带额外要求
```

侧边栏实时流式显示：总体评分 / 语法 / 地道性 / 句式 / 连贯性 / 改写版本 / 逐句讲解。结束后可选择一键替换为 AI 改写版。

### `:AETutor` — 逐句教学讲解

```vim
:'<,'>AETutor
```

对选中的英语文本逐句讲解：原句 / 句意（直译 + 地道意译）/ 语言点 / 更地道改写 / 扩展（同义词、短语、常见错误）。简洁精准，不堆术语。

### 表达积累库

```vim
:'<,'>AESave          " 把当前选中的好表达存起来
:AESearch startup     " 模糊搜索包含 startup 的表达
:AEPaste              " 打开完整库选择插入
```

存储路径：`~/.vim/ai_store/expressions/expressions.json`

### 发音辅助

```vim
:AESay                       " 朗读光标下的词（macOS Samantha 声音）
:'<,'>AEPhonetic             " 生成音标、发音要点、例句
```

---

## 对话功能

### 文件包含

在对话中使用 `>>> include` 指令：

```
>>> include
/path/to/file.py
/path/to/dir/**/*.js
```

支持 glob 模式。

### 聊天选项（对话文件内）

```
[chat-options]
model=qwen-max
temperature=0.5

>>> user
你好
```

### 窗口预设

| 预设 | 描述 |
|------|------|
| `right` | 右侧 75% 窗口（默认） |
| `left` | 左侧 50% 窗口 |
| `top` | 顶部 |
| `bottom` | 底部 |
| `tab` | 新标签页 |
| `float` | 浮动窗口 |

```vim
let g:vim_ai = {
\  'chat': {'window': {'preset': 'bottom'}},
\}
```

---

## 持久化存储

所有数据统一存储在 `~/.vim/ai_store/`：

```
~/.vim/ai_store/
├── conversations/    # 对话历史（JSON，按时间命名）
├── prompts/          # 自定义提示词（纯文本）
├── expressions/      # 英语表达积累库（JSON）
└── audit/            # Tool Calling shell 审计日志（按天轮转）
```

可通过配置覆盖根目录：

```vim
let g:vim_ai = {
\  'store_root': '~/my-ai-data',
\}
```

---

## 代码结构可视化

内置类似 tagbar 的代码结构树视图（Python / Go / JavaScript / TypeScript / Vimscript / Markdown）：

| 命令 | 描述 |
|------|------|
| `:AIStructure` | 切换结构窗口（右侧 30 列） |
| `:AIStructureOpen` | 打开结构窗口 |
| `:AIStructureClose` | 关闭 |
| `:AIStructureRefresh` | 手动刷新 |

光标移动自动同步高亮居中；回车跳转；支持 `<CR>` 跳转到对应行、`r` 刷新、`q` 关闭。

---

## Token 用量

每次 AI 请求完成后，command line 自动显示 token 用量：

```
Done. [in:1523, out:487, total:2010]
```

---

## 快捷键建议

```vim
" AI 核心
nnoremap <leader>a :AI<CR>
xnoremap <leader>a :AI<CR>
nnoremap <leader>c :AIChat<CR>
nnoremap <leader>r :AIRedo<CR>

" 英语辅助
nnoremap <leader>ec :AECheck<CR>
nnoremap <leader>ew :AEWrite<CR>
nnoremap <leader>et :AETutor<CR>
nnoremap <leader>es :AESay<CR>

" 陪伴
nnoremap <leader>ao :AICompanionOn<CR>
nnoremap <leader>af :AICompanionOff<CR>

" 结构视图
nnoremap <leader>st :AIStructure<CR>
```

---

## 架构

```
plugin/vim-ai.vim              → 入口命令注册
autoload/
├── vim_ai.vim                 → 核心编排层（补全/聊天渲染、vimcmd 执行、FormatUsage）
├── vim_ai_http.vim            → 网络层（ChatStream 流式 + ChatOnce 异步非流式）
├── vim_ai_config.vim          → 集中配置 + Get('a.b.c') 便捷读取
├── vim_ai_roles.vim           → 角色系统（INI 解析、缓存、热加载）
├── vim_ai_context.vim         → 自动上下文注入（git + 光标窗口）
├── vim_ai_tools.vim           → Tool Calling 注册中心 + 多轮编排器
├── vim_ai_prompt.vim          → 提示词工程（全异步回调）
├── vim_ai_english.vim         → 英语写作辅助（Check/Write/Tutor/TTS/表达库）
├── vim_ai_companion.vim       → 陪伴编写（编辑量累积 + 定时器判断 + 冷却期）
├── vim_ai_store.vim           → 持久化存储（对话/提示词/审计）
└── vim_ai_structure.vim       → 代码结构可视化（多语言）
```

---

## License

MIT
