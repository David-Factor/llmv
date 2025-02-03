local M = {}
local api = vim.api

-- Function to extract chat history (keep your existing implementation)
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
			latest_prompt = current_prompt -- Keep track of the latest prompt
		elseif in_response then
			-- Accumulate response text
			current_response = (current_response == "" and line or (current_response .. "\n" .. line))
		end
	end

	-- Check if we ended with a prompt (no response yet)
	if in_prompt and current_prompt and current_prompt ~= "" then
		latest_prompt = current_prompt
	-- If we ended with a completed pair, add it to history
	elseif current_prompt and current_response then
		table.insert(chat_history, { role = "user", content = current_prompt })
		table.insert(chat_history, { role = "assistant", content = current_response })
	end

	-- Debug prints
	print("Chat history entries:", #chat_history)
	print("Latest prompt:", latest_prompt)

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

-- Function to handle streaming response
local function handle_stream_line(data_line)
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
		return
	end

	local content = decoded.choices
		and decoded.choices[1]
		and decoded.choices[1].delta
		and decoded.choices[1].delta.content

	if not content or content == "" then
		return
	end

	-- Update buffer
	local lines = api.nvim_buf_get_lines(0, 0, -1, false)

	-- Remove Loading... if present
	if #lines > 0 and lines[#lines] == "Loading..." then
		table.remove(lines)
	end

	-- Split content into lines if it contains newlines
	local content_lines = vim.split(content, "\n")

	-- Handle each line of content
	for i, content_line in ipairs(content_lines) do
		if i == 1 then
			-- First line: append to last existing line or create new line
			local last_line = #lines > 0 and lines[#lines] or ""
			if last_line == "" then
				table.insert(lines, content_line)
			else
				lines[#lines] = last_line .. content_line
			end
		else
			-- Additional lines: add as new lines
			table.insert(lines, content_line)
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

	local api_key = os.getenv("OPENAI_API_KEY")
	-- local api_key =
	-- 	"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"
	if not api_key then
		print("Error: OPENAI_API_KEY is not set.")
		return
	end

	-- Prepare messages
	local messages = {
		{ role = "system", content = "You are a helpful AI. Respond concisely." },
	}
	for _, msg in ipairs(chat_history) do
		table.insert(messages, msg)
	end
	table.insert(messages, { role = "user", content = new_prompt })

	-- Prepare JSON data
	local json_data = vim.json.encode({
		model = "gpt-4",
		messages = messages,
		stream = true,
	})

	-- Initialize response in buffer
	stream_response_init()

	-- Make the request using vim.fn.jobstart
	vim.fn.jobstart({
		"curl",
		"-N", -- Disable buffering
		"-s", -- Silent mode
		"https://api.openai.com/v1/chat/completions",
		"-H",
		"Content-Type: application/json",
		"-H",
		"Authorization: Bearer " .. api_key,
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
			if code ~= 0 then
				print("Request failed with exit code:", code)
			end
		end,
	})
end

return M
