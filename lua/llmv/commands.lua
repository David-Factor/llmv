local M = {}

function M.register()
	vim.api.nvim_create_user_command("Run", function()
		require("llmv.core").run_llm()
	end, { desc = "Run LLM chat completion" })

	vim.api.nvim_create_user_command("Stop", function()
		require("llmv.core").stop_llm()
	end, { desc = "Stop current LLM request" })
end

return M
