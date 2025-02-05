local M = {}
local api = vim.api

-- Function to extract chat history
local function extract_chat_parts()
	local lines = api.nvim_buf_get_lines(0, 0, -1, false)
	local chat_history = {}
	local latest_prompt = nil
	local current_prompt = nil
	local current_response = nil
	local in_prompt = false
	local in_response = false

	for _, line in ipairs(lines) do
		if line:match("^>>>") then
			-- If we were in a response, store the completed pair
			if current_prompt and current_response then
				table.insert(chat_history, { role = "user", content = current_prompt })
				table.insert(chat_history, { role = "assistant", content = current_response })
			end
			-- Start new prompt
			in_prompt = true
			in_response = false
			current_prompt = ""
		elseif line:match("^<<<") then
			in_prompt = false
			in_response = true
			current_response = ""
		elseif in_prompt then
			-- Accumulate prompt text
			current_prompt = (current_prompt == "" and line or (current_prompt .. "\n" .. line))
			latest_prompt = current_prompt
		elseif in_response then
			-- Accumulate response text
			current_response = (current_response == "" and line or (current_response .. "\n" .. line))
		end
	end

	-- Handle the last prompt if it exists
	if in_prompt and current_prompt and current_prompt ~= "" then
		latest_prompt = current_prompt
		local original_lines = api.nvim_buf_get_lines(0, 0, -1, false)
		local output_lines = {}
		local last_line_index = #original_lines

		-- Find all bash commands and collect their outputs
		local command_outputs = {}
		for line in latest_prompt:gmatch("[^\n]+") do
			if line:match("^%s*@bash%(`.*`%)%s*$") then
				-- Extract and execute the command
				local command = line:match("^%s*@bash%(`(.+)`%)%s*$")
				print("Line:", vim.inspect(line)) -- Debug line content
				print("Command extraction attempt:", vim.inspect(command)) -- Debug extraction
				print("Extracted command:", vim.inspect(command)) -- Debug print

				if not command then
					print("Failed to extract command from line:", line)
					goto continue
				end

				local handle = io.popen(command)

				if handle then
					local result = handle:read("*a"):gsub("%s+$", "")
					handle:close()

					-- Store output lines for this command
					local cmd_output = {}
					table.insert(cmd_output, "# Output")
					for result_line in result:gsub("\r\n?", "\n"):gmatch("[^\n]*") do
						if result_line ~= "" then
							table.insert(cmd_output, result_line)
						end
					end
					table.insert(cmd_output, "# End Output")
					table.insert(cmd_output, "")

					-- Store in our collection
					table.insert(command_outputs, cmd_output)
				end
				::continue::
			end
		end

		-- Now combine everything
		local result_lines = {}
		local output_index = 1
		for line in latest_prompt:gmatch("[^\n]+") do
			table.insert(result_lines, line)
			if line:match("@bash%(`.-`%)") and command_outputs[output_index] then
				for _, output_line in ipairs(command_outputs[output_index]) do
					table.insert(result_lines, output_line)
				end
				output_index = output_index + 1
			end
		end

		-- Set all the lines at once
		api.nvim_buf_set_lines(0, 0, -1, false, result_lines)
	elseif current_prompt and current_response then
		table.insert(chat_history, { role = "user", content = current_prompt })
		table.insert(chat_history, { role = "assistant", content = current_response })
	end

	return chat_history, latest_prompt
end

-- Function to initialize response in buffer
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

-- Main function to make the API request
function M.run_llm()
	local chat_history, new_prompt = extract_chat_parts()
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

	-- Initialize response in buffer
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
				print("Received stdout data:", vim.inspect(data))
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
				print("Received stderr data:", vim.inspect(data))
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
end

return M

