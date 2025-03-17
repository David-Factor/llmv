local M = {}

-- Store all registered providers
M.providers = {}

-- Register a new provider
function M.register(name, provider)
	M.providers[name] = provider
end

-- Get a provider by name
function M.get(name)
	return M.providers[name]
end

-- Load built-in providers
local anthropic = require("llmv.providers.anthropic")
M.register("anthropic", anthropic)

return M

