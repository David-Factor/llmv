local provider = {
	name = "anthropic",
	current_job = nil,
	options = nil,
}

function provider.setup(opts)
	provider.options = opts or {}
	provider.options.model = provider.options.model or "claude-3-5-sonnet-20241022"
	provider.options.max_tokens = provider.options.max_tokens or 4096
	provider.options.temperature = provider.options.temperature or 0.7
end

function provider.complete(messages, callbacks)
	local api_key = os.getenv("ANTHROPIC_API_KEY")
	if not api_key then
		if callbacks.on_error then
			callbacks.on_error("ANTHROPIC_API_KEY is not set")
		end
		return false
	end

	-- Make API request
	local json_data = vim.json.encode({
		model = provider.options.model,
		messages = messages,
		stream = true,
		max_tokens = provider.options.max_tokens,
		temperature = provider.options.temperature,
	})

	provider.current_job = vim.fn.jobstart({
		"curl",
		"-N",
		"-s",
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
			if not data then
				return
			end
			for _, line in ipairs(data) do
				if line ~= "" then
					vim.schedule(function()
						local content = line:gsub("^data: ", "")
						if content == "[DONE]" then
							if callbacks.on_complete then
								callbacks.on_complete()
							end
							return
						end

						local ok, decoded = pcall(vim.json.decode, content)
						if not ok then
							return
						end

						content = decoded.delta and decoded.delta.text
						if content and content ~= "" and callbacks.on_chunk then
							callbacks.on_chunk(content)
						end
					end)
				end
			end
		end,
		on_stderr = function(_, data)
			if not data then
				return
			end
			for _, line in ipairs(data) do
				if line ~= "" and callbacks.on_error then
					callbacks.on_error(line)
				end
			end
		end,
	})

	return true
end

function provider.stop()
	if provider.current_job then
		vim.fn.jobstop(provider.current_job)
		provider.current_job = nil
		return true
	end
	return false
end

-- DO NOT require the module here; we'll register this provider from providers/init.lua

return provider

