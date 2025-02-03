local M = {}

M.core = require("llmv.core")
M.commands = require("llmv.commands")

function M.setup(opts)
	opts = opts or {}
	M.commands.register()
	print("llmv plugin loaded!")
	M.options = opts
end

return M
