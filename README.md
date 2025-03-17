# LLMV - LLM in your vim

> LLMs in Neovim, the Unix way

LLMV brings AI assistance into your editor using simple, composable tools you already know. No special buffers, no complex UI - just Markdown files and shell commands.

![GitHub License](https://img.shields.io/github/license/David-Factor/llmv)

![LLMV Demo](images/example.png)


## 🔍 Overview

LLMV turns Neovim into a powerful AI programming environment by:

- Using plain **Markdown files** - Get syntax highlighting and version control for free
- Leveraging your **shell** - Compose with `git`, `grep`, `curl`, or any CLI tool
- Staying **simple** - No new syntax to learn beyond `@bash()`

## 📝 Basic Syntax

LLMV uses a simple prompt/response format:

- `>>>` starts your prompt to the LLM
- `<<<` marks the LLM's response

For example:
```markdown
>>> What is 2+2?

<<< 
The answer is 4.

>>> Tell me about this file:
@bash(`cat myfile.txt`)
<output>
cat: myfile.txt: No such file or directory
</output>


<<< 
Based on the file contents...
```

All communication happens in regular Markdown files. Write your prompt after `>>>`, then use `:Run` to get a response. The response will appear below, starting with `<<<`.

## ✨ See It In Action

````markdown
>>> Help me optimize this function
@bash(`cat -n src/slow_function.py`)
<output>
     1	def process_items(items):
     2	    result = []
     3	    for item in items:
     4	        if item.is_valid():
     5	            result.append(item.transform())
     6	    return result
</output>

<<< 
Here's how we can improve the performance by using list comprehension 
and avoiding repeated method calls:

```python
def process_items(items):
    return [item.transform() for item in items if item.is_valid()]
```

This change:
1. Reduces memory allocations
2. Avoids repeated method lookups
3. Uses Python's optimized list comprehension

>>> Apply this change and show me the diff
@bash(`git diff src/slow_function.py`)
<output>
diff --git a/src/slow_function.py b/src/slow_function.py
index a23bf35..7d2f3bc 100644
--- a/src/slow_function.py
+++ b/src/slow_function.py
@@ -1,6 +1,2 @@
 def process_items(items):
-    result = []
-    for item in items:
-        if item.is_valid():
-            result.append(item.transform())
-    return result
+    return [item.transform() for item in items if item.is_valid()]
</output>
````

## 🚀 Quick Start

1. Install with your favorite package manager:
```lua
-- Using lazy.nvim
{
    'David-Factor/llmv',
    cmd = { "Run", "Stop" },
    config = true,
}
```

2. Set your API key:
```bash
export ANTHROPIC_API_KEY='your-api-key-here'  # For Claude AI (default)
```

3. Start chatting:
```markdown
>>> What's in this directory?
@bash(`ls -la`)
<output>
total 376
drwxr-xr-x@ 12 davidfactor  staff    384 17 Mar 20:35 .
drwxr-xr-x@ 12 davidfactor  staff    384 17 Mar 20:25 ..
-rw-r--r--@  1 davidfactor  staff    335 25 Feb 22:58 TODO.md
-rw-r--r--@  1 davidfactor  staff    220 15 Feb 00:33 diff.md
-rw-r--r--@  1 davidfactor  staff  18194 25 Feb 22:29 first_release.md
-rw-r--r--@  1 davidfactor  staff  10590 15 Feb 00:27 foo.md
-rw-r--r--@  1 davidfactor  staff      0 17 Mar 20:31 foop.md
-rw-r--r--@  1 davidfactor  staff  78035 25 Feb 22:29 local_models.md
-rw-r--r--@  1 davidfactor  staff      0 17 Mar 20:35 new_readme.md
-rw-r--r--@  1 davidfactor  staff    283 17 Mar 20:28 plugins.md
-rw-r--r--@  1 davidfactor  staff  34407 25 Feb 22:57 provider.md
-rw-r--r--@  1 davidfactor  staff  27971 25 Feb 21:52 relative_files.md
</output>

```

4. Run with `:Run` (or stop with `:Stop`)


## 🔧 How It Works
LLMV uses a simple but powerful pattern:
1. **File Access**: `@bash()` commands give the LLM quick access to your project. Commands are executed relative to the current file's directory:
   ```markdown
   >>> What's in this file?
   @bash(`cat ../src/myfile.py`)  # Relative to current file's location
   <output>
   def hello():
       print("Hello World")
   </output>
   ```

2. **Command Evaluation**: Only the most recent prompt's commands are run when you execute `:Run`

3. **Context Building**: The command output becomes part of the prompt:
   ```markdown
   >>> Update this function to be async
   @bash(`cat -n server.js`)
<output>
cat: server.js: No such file or directory
</output>

   <output>
   1  function getData() {
   2    return db.query('SELECT * FROM users')
   3  }
   </output>
   
   <<< Here's an async version of your function:
   
   ```javascript
   async function getData() {
     return await db.query('SELECT * FROM users')
   }
   ```
   ```

4. **Response Handling**: Responses are streamed in real-time and can be stopped with `:Stop`

## ⚠️ Security Note

LLMV uses bash commands to provide quick access to your filesystem and make that context available in prompts. However, this comes with important security considerations:

- Only the most recent prompt's commands are evaluated when you run `:Run`
- Commands have the same permissions as your Neovim process
- Be cautious with prompts from untrusted sources
- Review commands and their output before sending to the LLM
- Consider the security implications of sharing command output

Remember: The `@bash()` feature is a sharp tool - powerful but requires careful handling.

## 💡 Common Workflows

### Code Reviews
```markdown
>>> Review these changes for security issues:
@bash(`git diff main`)
<output>
diff --git a/.gitignore b/.gitignore
index d1e5bf3..f36b0c1 100644
--- a/.gitignore
+++ b/.gitignore
@@ -52,3 +52,5 @@ __pycache__/
 
 .envrc
 .env
+
+prompts/
diff --git a/lua/llmv/core.lua b/lua/llmv/core.lua
index 89991ab..efac918 100644
--- a/lua/llmv/core.lua
+++ b/lua/llmv/core.lua
@@ -1,8 +1,8 @@
 local M = {}
 local api = vim.api
 
-M.current_job = nil
 M.target_buf = nil
+M.options = {}
 
 local function get_current_file_dir()
 	local current_file = vim.fn.expand("%:p")
@@ -115,122 +115,109 @@ local function process_buffer()
 	return messages
 end
 
--- Handle streaming response
-local function handle_stream_line(line)
-	if not line or line == "" then
-		return
-	end
-
-	local content = line:gsub("^data: ", "")
-	if content == "[DONE]" then
-		return
-	end
-
-	local ok, decoded = pcall(vim.json.decode, content)
-	if not ok then
-		return
-	end
-
-	content = decoded.delta and decoded.delta.text
-	if not content or content == "" then
-		return
-	end
-
-	local lines = api.nvim_buf_get_lines(M.target_buf, 0, -1, false)
-	if lines[#lines] == "Loading..." then
-		table.remove(lines)
-	end
-
-	local new_lines = vim.split(content, "\n", { plain = true })
-	if #lines > 0 then
-		lines[#lines] = lines[#lines] .. new_lines[1]
-		for i = 2, #new_lines do
-			table.insert(lines, new_lines[i])
-		end
-	else
-		vim.list_extend(lines, new_lines)
-	end
-
-	api.nvim_buf_set_lines(M.target_buf, 0, -1, false, lines)
-end
-
 function M.run_llm()
-	local api_key = os.getenv("ANTHROPIC_API_KEY")
-	if not api_key then
-		print("Error: ANTHROPIC_API_KEY is not set")
-		return
-	end
-
 	M.target_buf = api.nvim_get_current_buf()
-
 	local messages = process_buffer()
 	if #messages == 0 then
 		print("No messages found")
 		return
 	end
 
-	-- Debug: Print messages being sent
-	print("Sending messages:", vim.inspect(messages))
-
-	-- Add response marker
-	local lines = api.nvim_buf_get_lines(0, 0, -1, false)
+	-- Add response marker - this is a UI concern that belongs in core
+	local lines = api.nvim_buf_get_lines(M.target_buf, 0, -1, false)
 	vim.list_extend(lines, { "<<<", "", "Loading..." })
 	api.nvim_buf_set_lines(M.target_buf, 0, -1, false, lines)
 
-	-- Make API request
-	local json_data = vim.json.encode({
-		model = "claude-3-5-sonnet-20241022",
-		messages = messages,
-		stream = true,
-		max_tokens = 4096,
-		temperature = 0.7,
-	})
+	-- Get the configured provider
+	local providers = require("llmv.providers")
+	local provider_name = M.options.provider or "anthropic"
+	local provider = providers.get(provider_name)
+
+	if not provider then
+		print("Provider not found: " .. provider_name)
+		return
+	end
 
-	M.current_job = vim.fn.jobstart({
-		"curl",
-		"-N",
-		"-s",
-		"https://api.anthropic.com/v1/messages",
-		"-H",
-		"Content-Type: application/json",
-		"-H",
-		"x-api-key: " .. api_key,
-		"-H",
-		"anthropic-version: 2023-06-01",
-		"--data-raw",
-		json_data,
-	}, {
-		stdout_buffered = false,
-		on_stdout = function(_, data)
-			if not data then
-				return
+	-- Run the provider's completion with callbacks
+	provider.complete(messages, {
+		on_chunk = function(content)
+			-- Update buffer with the new content
+			local buf_lines = api.nvim_buf_get_lines(M.target_buf, 0, -1, false)
+
+			-- Remove "Loading..." if it's there
+			if #buf_lines > 0 and buf_lines[#buf_lines] == "Loading..." then
+				table.remove(buf_lines)
 			end
-			for _, line in ipairs(data) do
-				if line ~= "" then
-					vim.schedule(function()
-						handle_stream_line(line)
-					end)
+
+			local new_lines = vim.split(content, "\n", { plain = true })
+			if #buf_lines > 0 then
+				buf_lines[#buf_lines] = buf_lines[#buf_lines] .. new_lines[1]
+				for i = 2, #new_lines do
+					table.insert(buf_lines, new_lines[i])
 				end
+			else
+				vim.list_extend(buf_lines, new_lines)
 			end
+
+			api.nvim_buf_set_lines(M.target_buf, 0, -1, false, buf_lines)
 		end,
-		on_stderr = function(_, data)
-			if not data then
-				return
-			end
-			for _, line in ipairs(data) do
-				if line ~= "" then
-					print("Error:", line)
-				end
+		on_error = function(err)
+			print("Error:", err)
+
+			-- Update buffer to show error
+			local buf_lines = api.nvim_buf_get_lines(M.target_buf, 0, -1, false)
+			-- Remove "Loading..." if it's there
+			if #buf_lines > 0 and buf_lines[#buf_lines] == "Loading..." then
+				table.remove(buf_lines)
+				table.insert(buf_lines, "Error: " .. err)
+				api.nvim_buf_set_lines(M.target_buf, 0, -1, false, buf_lines)
 			end
 		end,
+		on_complete = function()
+			-- Completion is handled implicitly as the buffer is already updated
+			-- Could add a notification or status message here if desired
+		end,
 	})
 end
 
 function M.stop_llm()
-	if M.current_job then
-		vim.fn.jobstop(M.current_job)
-		M.current_job = nil
-		print("Stopped LLM request")
+	local providers = require("llmv.providers")
+	local provider_name = M.options.provider or "anthropic"
+	local provider = providers.get(provider_name)
+
+	if provider and provider.stop then
+		if provider.stop() then
+			print("Stopped LLM request")
+
+			-- Update buffer to show stopped status
+			local buf_lines = api.nvim_buf_get_lines(M.target_buf, 0, -1, false)
+			-- Remove "Loading..." if it's there
+			if #buf_lines > 0 and buf_lines[#buf_lines] == "Loading..." then
+				table.remove(buf_lines)
+				table.insert(buf_lines, "[Request stopped]")
+				api.nvim_buf_set_lines(M.target_buf, 0, -1, false, buf_lines)
+			end
+		end
+	else
+		print("No active LLM request to stop")
+	end
+end
+
+function M.setup(opts)
+	M.options = opts or {}
+
+	-- Configure providers
+	local providers = require("llmv.providers")
+
+	-- Set up the default provider
+	local provider_name = M.options.provider or "anthropic"
+	local provider = providers.get(provider_name)
+
+	if provider then
+		local provider_opts = M.options.providers and M.options.providers[provider_name] or {}
+		provider.setup(provider_opts)
+	else
+		print("Warning: Provider not found: " .. provider_name)
 	end
 end
 
diff --git a/lua/llmv/init.lua b/lua/llmv/init.lua
index 977d050..2ed491a 100644
--- a/lua/llmv/init.lua
+++ b/lua/llmv/init.lua
@@ -1,13 +1,44 @@
 local M = {}
-
 M.core = require("llmv.core")
 M.commands = require("llmv.commands")
-
+M.providers = require("llmv.providers")
 function M.setup(opts)
 	opts = opts or {}
+
+	-- Default configuration
+	local default_provider = "anthropic"
+	opts.provider = opts.provider or default_provider
+	opts.providers = opts.providers or {}
+
+	-- Verify the requested provider exists
+	local provider = M.providers.get(opts.provider)
+	if not provider then
+		vim.notify(
+			"Warning: Provider '" .. opts.provider .. "' not found. Falling back to '" .. default_provider .. "'.",
+			vim.log.levels.WARN
+		)
+		opts.provider = default_provider
+
+		-- Check if we have the default provider
+		provider = M.providers.get(default_provider)
+		if not provider then
+			vim.notify(
+				"Error: Default provider '" .. default_provider .. "' not found. Plugin may not function correctly.",
+				vim.log.levels.ERROR
+			)
+			return -- Exit setup if we can't find the default provider
+		end
+	end
+
+	-- Ensure the provider has a configuration object (even if empty)
+	opts.providers[opts.provider] = opts.providers[opts.provider] or {}
+
+	-- Register commands
 	M.commands.register()
-	print("llmv plugin loaded!")
-	M.options = opts
-end
 
+	-- Setup core with options
+	M.core.setup(opts)
+
+	vim.notify("llmv plugin loaded with provider: " .. opts.provider, vim.log.levels.INFO)
+end
 return M
diff --git a/lua/llmv/providers/anthropic.lua b/lua/llmv/providers/anthropic.lua
new file mode 100644
index 0000000..a116d1d
--- /dev/null
+++ b/lua/llmv/providers/anthropic.lua
@@ -0,0 +1,101 @@
+local provider = {
+	name = "anthropic",
+	current_job = nil,
+	options = nil,
+}
+
+function provider.setup(opts)
+	provider.options = opts or {}
+	provider.options.model = provider.options.model or "claude-3-5-sonnet-20241022"
+	provider.options.max_tokens = provider.options.max_tokens or 8192
+	provider.options.temperature = provider.options.temperature or 0.7
+end
+
+function provider.complete(messages, callbacks)
+	local api_key = os.getenv("ANTHROPIC_API_KEY")
+	if not api_key then
+		if callbacks.on_error then
+			callbacks.on_error("ANTHROPIC_API_KEY is not set")
+		end
+		return false
+	end
+
+	-- Make API request
+	local json_data = vim.json.encode({
+		model = provider.options.model,
+		messages = messages,
+		stream = true,
+		max_tokens = provider.options.max_tokens,
+		temperature = provider.options.temperature,
+	})
+
+	provider.current_job = vim.fn.jobstart({
+		"curl",
+		"-N",
+		"-s",
+		"https://api.anthropic.com/v1/messages",
+		"-H",
+		"Content-Type: application/json",
+		"-H",
+		"x-api-key: " .. api_key,
+		"-H",
+		"anthropic-version: 2023-06-01",
+		"--data-raw",
+		json_data,
+	}, {
+		stdout_buffered = false,
+		on_stdout = function(_, data)
+			if not data then
+				return
+			end
+			for _, line in ipairs(data) do
+				if line ~= "" then
+					vim.schedule(function()
+						local content = line:gsub("^data: ", "")
+						if content == "[DONE]" then
+							if callbacks.on_complete then
+								callbacks.on_complete()
+							end
+							return
+						end
+
+						local ok, decoded = pcall(vim.json.decode, content)
+						if not ok then
+							return
+						end
+
+						content = decoded.delta and decoded.delta.text
+						if content and content ~= "" and callbacks.on_chunk then
+							callbacks.on_chunk(content)
+						end
+					end)
+				end
+			end
+		end,
+		on_stderr = function(_, data)
+			if not data then
+				return
+			end
+			for _, line in ipairs(data) do
+				if line ~= "" and callbacks.on_error then
+					callbacks.on_error(line)
+				end
+			end
+		end,
+	})
+
+	return true
+end
+
+function provider.stop()
+	if provider.current_job then
+		vim.fn.jobstop(provider.current_job)
+		provider.current_job = nil
+		return true
+	end
+	return false
+end
+
+-- DO NOT require the module here; we'll register this provider from providers/init.lua
+
+return provider
diff --git a/lua/llmv/providers/init.lua b/lua/llmv/providers/init.lua
new file mode 100644
index 0000000..e272a0f
--- /dev/null
+++ b/lua/llmv/providers/init.lua
@@ -0,0 +1,21 @@
+local M = {}
+
+-- Store all registered providers
+M.providers = {}
+
+-- Register a new provider
+function M.register(name, provider)
+	M.providers[name] = provider
+end
+
+-- Get a provider by name
+function M.get(name)
+	return M.providers[name]
+end
+
+-- Load built-in providers
+local anthropic = require("llmv.providers.anthropic")
+M.register("anthropic", anthropic)
+
+return M
+
</output>


Here's our current security policy:
@bash(`cat SECURITY.md`)
<output>
cat: SECURITY.md: No such file or directory
</output>

```

### Debugging
```markdown
>>> Help debug this test failure:
@bash(`cat test_output.log`)
<output>
cat: test_output.log: No such file or directory
</output>


Here's the relevant code:
@bash(`cat -n tests/auth_test.py`)
<output>
cat: tests/auth_test.py: No such file or directory
</output>

```

### Project Analysis
```markdown
>>> Analyze my project architecture:
@bash(`code2prompt ./my-project && pbpaste`)
<output>
[!] Failed to build directory tree: No such file or directory (os error 2)
</output>

```

### Generate and Apply Changes
```markdown
>>> Update this file to use async/await:
@bash(`cat -n src/callback_hell.js`)
<output>
cat: src/callback_hell.js: No such file or directory
</output>


# Apply the suggested changes:
@bash(`echo 'DIFF' | git apply`)
<output>
error: No valid patches in input (allow with "--allow-empty")
</output>

```

### Project Navigation

```markdown
>>> Show me the project structure:
@bash(`tree ..`)  # Navigate up one directory from current file
```


## 📖 Detailed Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    'David-Factor/llmv',
    cmd = { "Run", "Stop" },  -- Load plugin when these commands are used
    config = function()
        require('llmv').setup({
            -- Optional configuration
            provider = "anthropic", -- Default provider
            providers = {
                anthropic = {
                    model = "claude-3-5-sonnet-20241022", -- Default model
                    max_tokens = 8192,
                    temperature = 0.7,
                }
            }
        })
    end,
}
```

### [LazyVim](https://www.lazyvim.org/)

```lua
-- ~/.config/nvim/lua/plugins/llmv.lua
return {
    'David-Factor/llmv',
    cmd = { "Run", "Stop" },
    opts = {
        provider = "anthropic", -- Default provider
        providers = {
            anthropic = {
                model = "claude-3-5-sonnet-20241022", -- Default model
                max_tokens = 8192,
                temperature = 0.7,
            }
        }
    },
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
    'David-Factor/llmv',
    config = function()
        require('llmv').setup({
            -- Optional configuration
            provider = "anthropic", -- Default provider
            providers = {
                anthropic = {
                    model = "claude-3-5-sonnet-20241022", -- Default model
                    max_tokens = 8192,
                    temperature = 0.7,
                }
            }
        })
    end
}
```

## 🛠️ Commands

- `:Run` - Execute the current prompt
- `:Stop` - Stop the current LLM request

## ⌨️ Keybindings

You can map the commands to keys in your Neovim config. For example:

```lua
-- Map <leader>r to :Run
vim.keymap.set('n', '<leader>r', ':Run<CR>', { desc = 'Run LLM prompt' })

-- Map <leader>s to :Stop
vim.keymap.set('n', '<leader>s', ':Stop<CR>', { desc = 'Stop LLM request' })
```

Or if using LazyVim, you can add the keymaps in your plugin spec:

```lua
-- ~/.config/nvim/lua/plugins/llmv.lua
return {
    'David-Factor/llmv',
    cmd = { "Run", "Stop" },
    keys = {
        { "<leader>r", ":Run<CR>", desc = "Run LLM prompt" },
        { "<leader>s", ":Stop<CR>", desc = "Stop LLM request" },
    },
    opts = {
        provider = "anthropic",
        providers = {
            anthropic = {
                model = "claude-3-5-sonnet-20241022",
                max_tokens = 8192,
                temperature = 0.7,
            }
        }
    },
}
```

## 🔌 Providers

LLMV now supports a provider system for different LLM backends:

### Currently Supported

- **Anthropic (Claude)** - Default provider
  - Requires `ANTHROPIC_API_KEY` environment variable
  - Configurable model, max tokens, and temperature

### Configuration

```lua
require('llmv').setup({
    provider = "anthropic", -- Which provider to use
    providers = {
        anthropic = {
            model = "claude-3-5-sonnet-20241022", -- Model to use
            max_tokens = 8192, -- Maximum tokens in response
            temperature = 0.7, -- Response randomness (0-1)
        }
    }
})
```

## 🗺️ Roadmap

- Support for additional LLM providers (OpenAI, Ollama, etc.)
- Custom prompt templates
- Response formatting options

## 🤝 Contributing

Contributions welcome! Feel free to submit a Pull Request.

## 📝 License

MIT License

## 💌 Acknowledgments

- [llm-md](https://gitlab.com/anuna/llm-md) by Hugo O'Connor - The main inspiration for this project. While Hugo's tool is a full Racket, LLMV is more of a Scheme - a minimal, Neovim-specific interpretation of the same elegant idea.
