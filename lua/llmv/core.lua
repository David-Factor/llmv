local M = {}
local api = vim.api

-- Function to execute bash commands asynchronously
local function execute_bash_commands(prompt, callback)
	local command_count = 0
	local completed_commands = 0
	local result_lines = {}
	local command_outputs = {}

	-- First pass: count commands and prepare result lines
	for line in prompt:gmatch("[^\n]+") do
		if line:match("^%s*@bash%(`.*`%)%s*$") then
			command_count = command_count + 1
		end
		table.insert(result_lines, line)
	end

	-- If no commands, call callback immediately
	if command_count == 0 then
		callback(result_lines)
		return
	end

	-- Second pass: execute commands
	local current_cmd = 0
	for i, line in ipairs(result_lines) do
		if line:match("^%s*@bash%(`.*`%)%s*$") then
			current_cmd = current_cmd + 1
			local cmd_index = current_cmd
			local command = line:match("^%s*@bash%(`(.+)`%)%s*$")

			if command then
				vim.fn.jobstart(command, {
					stdout_buffered = true,
					stderr_buffered = true,
					on_stdout = function(_, data)
						if data then
							local cmd_output = {}
							table.insert(cmd_output, "# Output")
							for _, result_line in ipairs(data) do
								if result_line ~= "" then
									table.insert(cmd_output, result_line)
								end
							end
							table.insert(cmd_output, "# End Output")
							table.insert(cmd_output, "")
							command_outputs[cmd_index] = cmd_output
						end
					end,
					on_exit = function()
						completed_commands = completed_commands + 1
						if completed_commands == command_count then
							-- All commands completed, combine results
							local final_lines = {}
							local output_index = 1
							for _, result_line in ipairs(result_lines) do
								table.insert(final_lines, result_line)
								if result_line:match("@bash%(`.-`%)") and command_outputs[output_index] then
									for _, output_line in ipairs(command_outputs[output_index]) do
										table.insert(final_lines, output_line)
									end
									output_index = output_index + 1
								end
							end
							callback(final_lines)
						end
					end,
				})
			end
		end
	end
end

-- Function to extract chat history
local function extract_chat_parts(callback)
	local lines = api.nvim_buf_get_lines(0, 0, -1, false)
	local chat_history = {}
	local latest_prompt = nil
	local current_prompt = nil
	local current_response = nil
	local in_prompt = false
	local in_response = false
	local last_prompt_index = nil -- will store the line number where the new prompt begins

	for i, line in ipairs(lines) do
		if line:match("^>>>") then
			-- Before starting a new prompt, if we already had one completed, add it to chat history.
			if current_prompt and current_response then
				table.insert(chat_history, { role = "user", content = current_prompt })
				table.insert(chat_history, { role = "assistant", content = current_response })
			end
			in_prompt = true
			in_response = false
			current_prompt = ""
			-- Record the line number of this prompt marker.
			last_prompt_index = i
		elseif line:match("^<<<") then
			in_prompt = false
			in_response = true
			current_response = ""
		elseif in_prompt then
			current_prompt = (current_prompt == "" and line or (current_prompt .. "\n" .. line))
			latest_prompt = current_prompt
		elseif in_response then
			current_response = (current_response == "" and line or (current_response .. "\n" .. line))
		end
	end

	-- If we are still inside a prompt, process any bash commands
	if in_prompt and latest_prompt and latest_prompt ~= "" then
		execute_bash_commands(latest_prompt, function(result_lines)
			-- Instead of replacing the entire buffer, preserve everything before the new prompt.
			local preserved_lines = {}
			if last_prompt_index and last_prompt_index > 1 then
				preserved_lines = vim.api.nvim_buf_get_lines(0, 0, last_prompt_index - 1, false)
			end
			-- Build the new buffer: preserved chat history + the processed prompt block.
			local new_buffer = {}
			for _, line in ipairs(preserved_lines) do
				table.insert(new_buffer, line)
			end
			for _, line in ipairs(result_lines) do
				table.insert(new_buffer, line)
			end
			api.nvim_buf_set_lines(0, 0, -1, false, new_buffer)
			callback(chat_history, table.concat(result_lines, "\n"))
		end)
	else
		if current_prompt and current_response then
			table.insert(chat_history, { role = "user", content = current_prompt })
			table.insert(chat_history, { role = "assistant", content = current_response })
		end
		callback(chat_history, latest_prompt)
	end
end

-- Rest of the code remains the same
local function stream_response_init()
	local lines = api.nvim_buf_get_lines(0, 0, -1, false)
	table.insert(lines, "<<<")
	table.insert(lines, "")
	table.insert(lines, "Loading...")
	api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

local function handle_stream_line(data_line)
	print("Processing line:", vim.inspect(data_line))
	if not data_line or data_line == "" then
		return
	end

	-- Remove "data: " prefix and handle [DONE]
	local clean_chunk = data_line:gsub("^data: ", "")
	if clean_chunk == "[DONE]" then
		return
	end

	-- Parse JSON and extract content
	local success, decoded = pcall(vim.json.decode, clean_chunk)
	if not success then
		print("JSON decode failed:", vim.inspect(clean_chunk))
		return
	end

	-- Claude's streaming format
	local content = decoded.delta and decoded.delta.text
	print("Extracted content:", vim.inspect(content))
	if not content or content == "" then
		return
	end

	-- Update buffer
	local lines = api.nvim_buf_get_lines(0, 0, -1, false)
	-- Remove Loading... if present
	if #lines > 0 and lines[#lines] == "Loading..." then
		table.remove(lines)
	end

	-- Handle content
	if content:match("\n") or content:match("```") then
		-- Split content into lines
		local content_lines = vim.split(content, "\n", { plain = true })
		for i, line in ipairs(content_lines) do
			if i == 1 and #lines > 0 then
				lines[#lines] = lines[#lines] .. line
			else
				table.insert(lines, line)
			end
		end
	else
		if #lines > 0 then
			lines[#lines] = lines[#lines] .. content
		else
			table.insert(lines, content)
		end
	end

	api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

function M.run_llm()
	extract_chat_parts(function(chat_history, new_prompt)
		if not new_prompt then
			print("No new prompt found.")
			return
		end

		local api_key = os.getenv("ANTHROPIC_API_KEY")
		if not api_key then
			print("Error: ANTHROPIC_API_KEY is not set.")
			return
		end

		-- Prepare messages in Claude's format
		local messages = {}
		for _, msg in ipairs(chat_history) do
			table.insert(messages, {
				role = msg.role == "user" and "user" or "assistant",
				content = msg.content,
			})
		end
		table.insert(messages, { role = "user", content = new_prompt })

		-- Debug log the messages being sent
		print("Messages being sent:", vim.inspect(messages))

		-- Prepare JSON data for Claude
		local json_data = vim.json.encode({
			model = "claude-3-5-sonnet-20241022",
			messages = messages,
			stream = true,
			max_tokens = 4096,
			temperature = 0.7,
		})

		print("Sending request to Claude API...")
		stream_response_init()

		-- Make the request using vim.fn.jobstart
		vim.fn.jobstart({
			"curl",
			"-N",
			"-s",
			"-v",
			"https://api.anthropic.com/v1/messages",
			"-H",
			"Content-Type: application/json",
			"-H",
			"x-api-key: " .. api_key,
			"-H",
			"anthropic-version: 2023-06-01",
			"--data-raw",
			json_data,
		}, {
			stdout_buffered = false,
			on_stdout = function(_, data)
				if data then
					for _, line in ipairs(data) do
						if line ~= "" then
							vim.schedule(function()
								handle_stream_line(line)
							end)
						end
					end
				end
			end,
			on_stderr = function(_, data)
				if data then
					for _, line in ipairs(data) do
						if line ~= "" then
							print("Error:", line)
						end
					end
				end
			end,
			on_exit = function(_, code)
				print("Request finished with code:", code)
				if code ~= 0 then
					print("Request failed with exit code:", code)
				end
			end,
		})
	end)
end

return M
