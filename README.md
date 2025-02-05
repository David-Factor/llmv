# LLMV - LLM in your vim

LLMV is a Neovim plugin that integrates Claude AI capabilities directly into your editor, allowing for seamless interaction with the Claude language model while maintaining your workflow.

## Features

- Direct integration with Claude AI
- Chat-like interface within Neovim
- Support for executing bash commands within prompts
- Streaming responses for real-time feedback
- Maintains chat history for context-aware conversations

## Prerequisites

- Neovim (0.5.0 or later)
- An Anthropic API key
- curl (for API requests)

## Installation

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
    'yourusername/llmv',
    config = function()
        require('llmv').setup()
    end
}
```

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    'yourusername/llmv',
    config = true
}
```

## Configuration

1. Set your Anthropic API key as an environment variable:

```bash
export ANTHROPIC_API_KEY='your-api-key-here'
```

2. Basic setup in your Neovim config:

```lua
require('llmv').setup({
    -- Optional configuration options here
})
```

## Usage

1. Start a new prompt by typing:

```
>>>
Your question or prompt here
```

2. Execute the prompt using the command:

```vim
:Run
```

3. The response will appear below your prompt, starting with:

```
<<<
Claude's response here
```

### Using Bash Commands in Prompts

You can include bash commands in your prompts using the `@bash()` syntax:

```
>>>
Show me the contents of the current directory
@bash(`ls -la`)
```

## Commands

- `:Run` - Execute the current prompt and get a response from Claude

## Example Interaction

```
>>> What's in my current directory?
@bash(`ls -la`)

<<< 
Based on the directory listing, you have:
[Claude's detailed response about your directory contents]

>>> Can you explain the Lua files in detail?
@bash(`cat lua/llmv/*.lua`)

<<<
[Claude's analysis of your Lua files]
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License

## Acknowledgments

- Anthropic for the Claude AI API
- The Neovim community

## Troubleshooting

If you encounter issues:

1. Verify your API key is correctly set
2. Check the Neovim logs for error messages
3. Ensure curl is installed and accessible
4. Verify your internet connection

For more help, please open an issue on the GitHub repository.
