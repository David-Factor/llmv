local M = {}
local api = vim.api

-- Process the current buffer and expand any bash commands
local function process_buffer()
    local lines = api.nvim_buf_get_lines(0, 0, -1, false)
    local result = {}
    local messages = {}
    local current = {}
    local in_user = false
    
    for i, line in ipairs(lines) do
        if line:match("^>>>") then
            if in_user and #current > 0 then
                table.insert(messages, { role = "user", content = table.concat(current, "\n") })
            end
            current = {}
            in_user = true
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
                table.insert(result, line)
                local output = vim.fn.system(cmd)
                if output and output ~= "" then
                    table.insert(result, "# Output")
                    for _, out_line in ipairs(vim.split(output, "\n", { trimempty = true })) do
                        table.insert(result, out_line)
                    end
                    table.insert(result, "# End Output")
                    table.insert(result, "")
                    -- Update current with expanded content
                    table.insert(current, line)
                    table.insert(current, "# Output")
                    for _, out_line in ipairs(vim.split(output, "\n", { trimempty = true })) do
                        table.insert(current, out_line)
                    end
                    table.insert(current, "# End Output")
                    table.insert(current, "")
                end
            else
                table.insert(result, line)
                if line ~= "" then
                    table.insert(current, line)
                end
            end
        end
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

-- Handle streaming response
local function handle_stream_line(line)
    if not line or line == "" then return end
    
    local content = line:gsub("^data: ", "")
    if content == "[DONE]" then return end
    
    local ok, decoded = pcall(vim.json.decode, content)
    if not ok then return end
    
    content = decoded.delta and decoded.delta.text
    if not content or content == "" then return end
    
    local lines = api.nvim_buf_get_lines(0, 0, -1, false)
    if lines[#lines] == "Loading..." then
        table.remove(lines)
    end
    
    local new_lines = vim.split(content, "\n", { plain = true })
    if #lines > 0 then
        lines[#lines] = lines[#lines] .. new_lines[1]
        for i = 2, #new_lines do
            table.insert(lines, new_lines[i])
        end
    else
        vim.list_extend(lines, new_lines)
    end
    
    api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

function M.run_llm()
    local api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key then
        print("Error: ANTHROPIC_API_KEY is not set")
        return
    end
    
    local messages = process_buffer()
    if #messages == 0 then
        print("No messages found")
        return
    end
    
    -- Debug: Print messages being sent
    print("Sending messages:", vim.inspect(messages))
    
    -- Add response marker
    local lines = api.nvim_buf_get_lines(0, 0, -1, false)
    vim.list_extend(lines, { "<<<", "", "Loading..." })
    api.nvim_buf_set_lines(0, 0, -1, false, lines)
    
    -- Make API request
    local json_data = vim.json.encode({
        model = "claude-3-5-sonnet-20241022",
        messages = messages,
        stream = true,
        max_tokens = 4096,
        temperature = 0.7,
    })
    
    vim.fn.jobstart({
        "curl", "-N", "-s",
        "https://api.anthropic.com/v1/messages",
        "-H", "Content-Type: application/json",
        "-H", "x-api-key: " .. api_key,
        "-H", "anthropic-version: 2023-06-01",
        "--data-raw", json_data,
    }, {
        stdout_buffered = false,
        on_stdout = function(_, data)
            if not data then return end
            for _, line in ipairs(data) do
                if line ~= "" then
                    vim.schedule(function()
                        handle_stream_line(line)
                    end)
                end
            end
        end,
        on_stderr = function(_, data)
            if not data then return end
            for _, line in ipairs(data) do
                if line ~= "" then
                    print("Error:", line)
                end
            end
        end
    })
end

return M