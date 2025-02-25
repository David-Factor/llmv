-- local M = {}
-- local api = vim.api
--
-- M.current_job = nil
-- M.target_buf = nil
--
-- local function get_current_file_dir()
-- 	local current_file = vim.fn.expand("%:p")
-- 	return vim.fn.fnamemodify(current_file, ":h")
-- end
--
-- -- Process the current buffer and expand any non evaluated bash commands
-- local function process_buffer()
-- 	local lines = api.nvim_buf_get_lines(0, 0, -1, false)
-- 	local result = {}
-- 	local messages = {}
-- 	local current = {}
-- 	local in_user = false
-- 	local i = 1
-- 	local file_dir = get_current_file_dir()
--
-- 	while i <= #lines do
-- 		local line = lines[i]
--
-- 		if line:match("^>>>%s*(.*)$") then
-- 			-- Push any accumulated content with the proper role
-- 			if #current > 0 then
-- 				local role = in_user and "user" or "assistant"
-- 				table.insert(messages, { role = role, content = table.concat(current, "\n") })
-- 			end
-- 			current = {}
-- 			in_user = true
-- 			-- Extract and add any text after ">>>"
-- 			local prompt_text = line:match("^>>>%s*(.*)$")
-- 			if prompt_text and prompt_text ~= "" then
-- 				table.insert(current, prompt_text)
-- 			end
-- 			table.insert(result, line)
-- 		elseif line:match("^<<<") then
-- 			if in_user and #current > 0 then
-- 				table.insert(messages, { role = "user", content = table.concat(current, "\n") })
-- 			end
-- 			current = {}
-- 			in_user = false
-- 			table.insert(result, line)
-- 		else
-- 			local cmd = line:match("^%s*@bash%(`(.+)`%)%s*$")
-- 			if cmd then
-- 				-- Check if this bash command has already been evaluated
-- 				local next_line = lines[i + 1]
-- 				if not (next_line and next_line:match("^<output>")) then
-- 					-- Command hasn't been evaluated yet
-- 					table.insert(result, line)
--
-- 					local cd_cmd = string.format("cd %q && %s", file_dir, cmd)
-- 					local output = vim.fn.system(cd_cmd)
-- 					if output and output ~= "" then
-- 						table.insert(result, "<output>")
-- 						for _, out_line in ipairs(vim.split(output, "\n", { trimempty = true })) do
-- 							table.insert(result, out_line)
-- 						end
-- 						table.insert(result, "</output>")
-- 						table.insert(result, "")
--
-- 						-- Add to current message including the output
-- 						table.insert(current, line)
-- 						table.insert(current, "<output>")
-- 						for _, out_line in ipairs(vim.split(output, "\n", { trimempty = true })) do
-- 							table.insert(current, out_line)
-- 						end
-- 						table.insert(current, "</output>")
-- 						table.insert(current, "")
-- 					end
-- 				else
-- 					-- Command has already been evaluated, copy existing command and output
-- 					table.insert(result, line)
-- 					while i + 1 <= #lines and not lines[i + 1]:match("^</output>$") do
-- 						i = i + 1
-- 						table.insert(result, lines[i])
-- 						table.insert(current, lines[i])
-- 					end
-- 					-- Add closing tag and empty line
-- 					if i + 1 <= #lines then
-- 						i = i + 1
-- 						table.insert(result, lines[i])
-- 						table.insert(current, lines[i])
-- 						if i + 1 <= #lines and lines[i + 1] == "" then
-- 							i = i + 1
-- 							table.insert(result, lines[i])
-- 							table.insert(current, lines[i])
-- 						end
-- 					end
-- 				end
-- 			else
-- 				table.insert(result, line)
-- 				if line ~= "" then
-- 					table.insert(current, line)
-- 				end
-- 			end
-- 		end
-- 		i = i + 1
-- 	end
--
-- 	-- Handle final message
-- 	if #current > 0 then
-- 		if in_user then
-- 			table.insert(messages, { role = "user", content = table.concat(current, "\n") })
-- 		else
-- 			table.insert(messages, { role = "assistant", content = table.concat(current, "\n") })
-- 		end
-- 	end
--
-- 	-- Update buffer with expanded content
-- 	api.nvim_buf_set_lines(0, 0, -1, false, result)
-- 	return messages
-- end
--
-- -- Handle streaming response
-- local function handle_stream_line(line)
-- 	if not line or line == "" then
-- 		return
-- 	end
--
-- 	local content = line:gsub("^data: ", "")
-- 	if content == "[DONE]" then
-- 		return
-- 	end
--
-- 	local ok, decoded = pcall(vim.json.decode, content)
-- 	if not ok then
-- 		return
-- 	end
--
-- 	content = decoded.delta and decoded.delta.text
-- 	if not content or content == "" then
-- 		return
-- 	end
--
-- 	local lines = api.nvim_buf_get_lines(M.target_buf, 0, -1, false)
-- 	if lines[#lines] == "Loading..." then
-- 		table.remove(lines)
-- 	end
--
-- 	local new_lines = vim.split(content, "\n", { plain = true })
-- 	if #lines > 0 then
-- 		lines[#lines] = lines[#lines] .. new_lines[1]
-- 		for i = 2, #new_lines do
-- 			table.insert(lines, new_lines[i])
-- 		end
-- 	else
-- 		vim.list_extend(lines, new_lines)
-- 	end
--
-- 	api.nvim_buf_set_lines(M.target_buf, 0, -1, false, lines)
-- end
--
-- function M.run_llm()
-- 	local api_key = os.getenv("ANTHROPIC_API_KEY")
-- 	if not api_key then
-- 		print("Error: ANTHROPIC_API_KEY is not set")
-- 		return
-- 	end
--
-- 	M.target_buf = api.nvim_get_current_buf()
--
-- 	local messages = process_buffer()
-- 	if #messages == 0 then
-- 		print("No messages found")
-- 		return
-- 	end
--
-- 	-- Debug: Print messages being sent
-- 	print("Sending messages:", vim.inspect(messages))
--
-- 	-- Add response marker
-- 	local lines = api.nvim_buf_get_lines(0, 0, -1, false)
-- 	vim.list_extend(lines, { "<<<", "", "Loading..." })
-- 	api.nvim_buf_set_lines(M.target_buf, 0, -1, false, lines)
--
-- 	-- Make API request
-- 	local json_data = vim.json.encode({
-- 		model = "claude-3-7-sonnet-20250219",
-- 		messages = messages,
-- 		stream = true,
-- 		max_tokens = 4096,
-- 		temperature = 0.7,
-- 	})
--
-- 	M.current_job = vim.fn.jobstart({
-- 		"curl",
-- 		"-N",
-- 		"-s",
-- 		"https://api.anthropic.com/v1/messages",
-- 		"-H",
-- 		"Content-Type: application/json",
-- 		"-H",
-- 		"x-api-key: " .. api_key,
-- 		"-H",
-- 		"anthropic-version: 2023-06-01",
-- 		"--data-raw",
-- 		json_data,
-- 	}, {
-- 		stdout_buffered = false,
-- 		on_stdout = function(_, data)
-- 			if not data then
-- 				return
-- 			end
-- 			for _, line in ipairs(data) do
-- 				if line ~= "" then
-- 					vim.schedule(function()
-- 						handle_stream_line(line)
-- 					end)
-- 				end
-- 			end
-- 		end,
-- 		on_stderr = function(_, data)
-- 			if not data then
-- 				return
-- 			end
-- 			for _, line in ipairs(data) do
-- 				if line ~= "" then
-- 					print("Error:", line)
-- 				end
-- 			end
-- 		end,
-- 	})
-- end
--
-- function M.stop_llm()
-- 	if M.current_job then
-- 		vim.fn.jobstop(M.current_job)
-- 		M.current_job = nil
-- 		print("Stopped LLM request")
-- 	end
-- end
--
-- return M

local M = {}
local api = vim.api

M.target_buf = nil
M.options = {}

local function get_current_file_dir()
	local current_file = vim.fn.expand("%:p")
	return vim.fn.fnamemodify(current_file, ":h")
end

-- Process the current buffer and expand any non evaluated bash commands
local function process_buffer()
	local lines = api.nvim_buf_get_lines(0, 0, -1, false)
	local result = {}
	local messages = {}
	local current = {}
	local in_user = false
	local i = 1
	local file_dir = get_current_file_dir()

	while i <= #lines do
		local line = lines[i]

		if line:match("^>>>%s*(.*)$") then
			-- Push any accumulated content with the proper role
			if #current > 0 then
				local role = in_user and "user" or "assistant"
				table.insert(messages, { role = role, content = table.concat(current, "\n") })
			end
			current = {}
			in_user = true
			-- Extract and add any text after ">>>"
			local prompt_text = line:match("^>>>%s*(.*)$")
			if prompt_text and prompt_text ~= "" then
				table.insert(current, prompt_text)
			end
			table.insert(result, line)
		elseif line:match("^<<<") then
			if in_user and #current > 0 then
				table.insert(messages, { role = "user", content = table.concat(current, "\n") })
			end
			current = {}
			in_user = false
			table.insert(result, line)
		else
			local cmd = line:match("^%s*@bash%(`(.+)`%)%s*$")
			if cmd then
				-- Check if this bash command has already been evaluated
				local next_line = lines[i + 1]
				if not (next_line and next_line:match("^<output>")) then
					-- Command hasn't been evaluated yet
					table.insert(result, line)

					local cd_cmd = string.format("cd %q && %s", file_dir, cmd)
					local output = vim.fn.system(cd_cmd)
					if output and output ~= "" then
						table.insert(result, "<output>")
						for _, out_line in ipairs(vim.split(output, "\n", { trimempty = true })) do
							table.insert(result, out_line)
						end
						table.insert(result, "</output>")
						table.insert(result, "")

						-- Add to current message including the output
						table.insert(current, line)
						table.insert(current, "<output>")
						for _, out_line in ipairs(vim.split(output, "\n", { trimempty = true })) do
							table.insert(current, out_line)
						end
						table.insert(current, "</output>")
						table.insert(current, "")
					end
				else
					-- Command has already been evaluated, copy existing command and output
					table.insert(result, line)
					while i + 1 <= #lines and not lines[i + 1]:match("^</output>$") do
						i = i + 1
						table.insert(result, lines[i])
						table.insert(current, lines[i])
					end
					-- Add closing tag and empty line
					if i + 1 <= #lines then
						i = i + 1
						table.insert(result, lines[i])
						table.insert(current, lines[i])
						if i + 1 <= #lines and lines[i + 1] == "" then
							i = i + 1
							table.insert(result, lines[i])
							table.insert(current, lines[i])
						end
					end
				end
			else
				table.insert(result, line)
				if line ~= "" then
					table.insert(current, line)
				end
			end
		end
		i = i + 1
	end

	-- Handle final message
	if #current > 0 then
		if in_user then
			table.insert(messages, { role = "user", content = table.concat(current, "\n") })
		else
			table.insert(messages, { role = "assistant", content = table.concat(current, "\n") })
		end
	end

	-- Update buffer with expanded content
	api.nvim_buf_set_lines(0, 0, -1, false, result)
	return messages
end

function M.run_llm()
	M.target_buf = api.nvim_get_current_buf()
	local messages = process_buffer()
	if #messages == 0 then
		print("No messages found")
		return
	end

	-- Add response marker - this is a UI concern that belongs in core
	local lines = api.nvim_buf_get_lines(M.target_buf, 0, -1, false)
	vim.list_extend(lines, { "<<<", "", "Loading..." })
	api.nvim_buf_set_lines(M.target_buf, 0, -1, false, lines)

	-- Get the configured provider
	local providers = require("llmv.providers")
	local provider_name = M.options.provider or "anthropic"
	local provider = providers.get(provider_name)

	if not provider then
		print("Provider not found: " .. provider_name)
		return
	end

	-- Run the provider's completion with callbacks
	provider.complete(messages, {
		on_chunk = function(content)
			-- Update buffer with the new content
			local buf_lines = api.nvim_buf_get_lines(M.target_buf, 0, -1, false)

			-- Remove "Loading..." if it's there
			if #buf_lines > 0 and buf_lines[#buf_lines] == "Loading..." then
				table.remove(buf_lines)
			end

			local new_lines = vim.split(content, "\n", { plain = true })
			if #buf_lines > 0 then
				buf_lines[#buf_lines] = buf_lines[#buf_lines] .. new_lines[1]
				for i = 2, #new_lines do
					table.insert(buf_lines, new_lines[i])
				end
			else
				vim.list_extend(buf_lines, new_lines)
			end

			api.nvim_buf_set_lines(M.target_buf, 0, -1, false, buf_lines)
		end,
		on_error = function(err)
			print("Error:", err)

			-- Update buffer to show error
			local buf_lines = api.nvim_buf_get_lines(M.target_buf, 0, -1, false)
			-- Remove "Loading..." if it's there
			if #buf_lines > 0 and buf_lines[#buf_lines] == "Loading..." then
				table.remove(buf_lines)
				table.insert(buf_lines, "Error: " .. err)
				api.nvim_buf_set_lines(M.target_buf, 0, -1, false, buf_lines)
			end
		end,
		on_complete = function()
			-- Completion is handled implicitly as the buffer is already updated
			-- Could add a notification or status message here if desired
		end,
	})
end

function M.stop_llm()
	local providers = require("llmv.providers")
	local provider_name = M.options.provider or "anthropic"
	local provider = providers.get(provider_name)

	if provider and provider.stop then
		if provider.stop() then
			print("Stopped LLM request")

			-- Update buffer to show stopped status
			local buf_lines = api.nvim_buf_get_lines(M.target_buf, 0, -1, false)
			-- Remove "Loading..." if it's there
			if #buf_lines > 0 and buf_lines[#buf_lines] == "Loading..." then
				table.remove(buf_lines)
				table.insert(buf_lines, "[Request stopped]")
				api.nvim_buf_set_lines(M.target_buf, 0, -1, false, buf_lines)
			end
		end
	else
		print("No active LLM request to stop")
	end
end

function M.setup(opts)
	M.options = opts or {}

	-- Configure providers
	local providers = require("llmv.providers")

	-- Set up the default provider
	local provider_name = M.options.provider or "anthropic"
	local provider = providers.get(provider_name)

	if provider then
		local provider_opts = M.options.providers and M.options.providers[provider_name] or {}
		provider.setup(provider_opts)
	else
		print("Warning: Provider not found: " .. provider_name)
	end
end

return M
