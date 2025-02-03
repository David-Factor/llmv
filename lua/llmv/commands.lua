local M = {}

function M.register()
	vim.api.nvim_create_user_command("Run", function()
		require("llmv.core").run_llm()
	end, { desc = "Append hello world to buffer" })
end

return M
