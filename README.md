# VimAI

VimAI is a powerful Vim plugin that integrates AI capabilities directly into your Vim editor. It allows you to use AI for text generation, code completion, editing, and interactive conversations without leaving your editor.

## Features

- **Text Completion**: Automatically complete text or code using AI
- **Text Editing**: Edit and improve existing text or code based on instructions
- **AI Chat**: Interactive conversation with AI in a separate window
- **File Inclusion**: Include content from other files in your chat
- **Role-Based Prompts**: Use predefined roles for different AI tasks
- **Custom Configuration**: Flexibly configure model parameters, UI behavior, and more

## Installation

### Requirements
- Vim with Python 3 support (`:echo has('python3')` should return 1)
- An OpenAI API key (or compatible API service)

### Using a Plugin Manager

The recommended installation method is to use a plugin manager such as Vundle, Pathogen, or Vim-Plug. Add the following line to your vimrc file:

```vim
Plug 'bobobocode/VimAI'
```

Then run the plugin installation command for your manager. For example, with Vim-Plug:

```vim
:PlugInstall
```

## Configuration

### API Key Setup

You need to set up your API key before using the plugin. You can do this in one of the following ways:

1. Set it in your vimrc:
   ```vim
   let g:ai_api_key = "your-api-key-here"
   ```

2. Store it in a configuration file (`~/.config/openai.token` by default):
   ```
   your-api-key-here
   ```

### Customizing Default Settings

You can customize various aspects of the plugin by adding configuration to your vimrc file. Here are some examples:

```vim
" Chat configuration
let g:vim_ai_chat = {
\  "options": {
\    "model": "gpt-4o",
\    "endpoint_url": "https://api.openai.com/v1/chat/completions",
\    "temperature": 0.7,
\  },
\  "ui": {
\    "open_chat_command": "preset_right",
\  },
\}

" Text completion configuration
let g:vim_ai_complete = {
\  "options": {
\    "model": "gpt-3.5-turbo-instruct",
\    "temperature": 0.1,
\  },
\}

" Text editing configuration
let g:vim_ai_edit = {
\  "options": {
\    "model": "gpt-3.5-turbo-instruct",
\    "temperature": 0.3,
\  },
\}
```

## Usage

### Basic Commands

| Command | Description |
|---------|-------------|
| `:AI` | Complete text on the current line or visual selection |
| `:AI {prompt}` | Complete the given prompt |
| `:AIChat` | Start or continue a conversation with AI |
| `:AINewChat` | Start a new conversation in a new window |
| `:AINewChat {preset}` | Start a new conversation with a window preset (below, tab, right) |
| `:AIRedo` | Repeat the last AI command |

### Text Editing

```vim
" Edit the current line
:AIEdit improve this text

" Edit a visual selection
:'<,'>AIEdit fix grammar and spelling
```

### AI Chat

```vim
" Start a new chat
:AIChat

" Start a chat with a prompt
:AIChat explain quantum computing

" Include files in your chat
:AIChat analyze this code
>>> include
/path/to/file.py
```

### Role-Based Commands

The plugin includes several role-based commands for common tasks:

| Command | Description |
|---------|-------------|
| `:AIp` | Explain the selected code |
| `:AIut` | Generate unit tests for the selected code |
| `:AIen` | Improve English expression of the selected text |
| `:AIw` | Complete code comments in the selected content |
| `:AIr` | Correct errors in the selected content |

## Key Bindings

You can set up key bindings in your vimrc file for quick access to the plugin's features:

```vim
" Complete text in normal and visual mode
nnoremap <leader>a :AI<CR>
xnoremap <leader>a :AI<CR>

" Edit text in normal and visual mode
nnoremap <leader>e :AIEdit<CR>
xnoremap <leader>e :AIEdit<CR>

" Start chat in normal and visual mode
nnoremap <leader>c :AIChat<CR>
xnoremap <leader>c :AIChat<CR>

" Redo last AI command
nnoremap <leader>r :AIRedo<CR>
```

## Advanced Features

### Chat Window Presets

You can configure where the chat window opens by setting the `open_chat_command` option or using one of the built-in presets:

- `preset_below`: Open chat window below current window
- `preset_tab`: Open chat in a new tab
- `preset_right`: Open chat window on the right side

### Role Configuration

You can define custom roles in a `.ini` file to create reusable prompts and configurations:

```vim
let g:vim_ai_roles_config_file = "/path/to/your/roles.ini"
```

Example role definition in `roles.ini`:

```ini
[grammar]
prompt = fix spelling and grammar

[grammar.options]
temperature = 0.4
```

## Debugging

To enable debugging, add the following to your vimrc:

```vim
let g:vim_ai_debug = 1
let g:vim_ai_debug_log_file = "/path/to/debug.log"
```

## Getting Help

In Vim, you can view the complete help documentation with:

```vim
:help vim-ai
```

## Notes

- Make sure you have correctly configured your API key before use
- The plugin requires Python 3 support
- Default model is GPT-4o for chat and GPT-3.5-turbo-instruct for completion and editing
- For large files or complex requests, you may need to adjust `max_tokens` and `request_timeout` parameters
