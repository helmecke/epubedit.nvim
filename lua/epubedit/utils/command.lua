local fn = vim.fn

local M = {}

function M.run(cmd, args, opts)
  opts = opts or {}
  local stdout, stderr = {}, {}
  local job_id = fn.jobstart(vim.list_extend({ cmd }, args or {}), {
    cwd = opts.cwd,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stdout, line)
        end
      end
    end,
    on_stderr = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stderr, line)
        end
      end
    end,
  })

  if job_id <= 0 then
    return false, string.format("failed to start %s", cmd)
  end

  local status = fn.jobwait({ job_id }, opts.timeout or 60000)[1]
  if status == -1 then
    fn.jobstop(job_id)
    return false, string.format("%s timed out", cmd)
  end

  if status ~= 0 then
    local message = table.concat(stderr, "\n")
    if message == "" then
      message = string.format("%s failed with exit code %d", cmd, status)
    end
    return false, message
  end

  return true, table.concat(stdout, "\n")
end

return M
