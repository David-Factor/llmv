local M = {}
M.core = require("llmv.core")
M.commands = require("llmv.commands")
M.providers = require("llmv.providers")
function M.setup(opts)
	opts = opts or {}

	-- Default configuration
	local default_provider = "anthropic"
	opts.provider = opts.provider or default_provider
	opts.providers = opts.providers or {}

	-- Verify the requested provider exists
	local provider = M.providers.get(opts.provider)
	if not provider then
		vim.notify(
			"Warning: Provider '" .. opts.provider .. "' not found. Falling back to '" .. default_provider .. "'.",
			vim.log.levels.WARN
		)
		opts.provider = default_provider

		-- Check if we have the default provider
		provider = M.providers.get(default_provider)
		if not provider then
			vim.notify(
				"Error: Default provider '" .. default_provider .. "' not found. Plugin may not function correctly.",
				vim.log.levels.ERROR
			)
			return -- Exit setup if we can't find the default provider
		end
	end

	-- Ensure the provider has a configuration object (even if empty)
	opts.providers[opts.provider] = opts.providers[opts.provider] or {}

	-- Register commands
	M.commands.register()

	-- Setup core with options
	M.core.setup(opts)

	vim.notify("llmv plugin loaded with provider: " .. opts.provider, vim.log.levels.INFO)
end
return M
