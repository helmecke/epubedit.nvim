local epubedit = require("epubedit")

vim.api.nvim_create_user_command("EpubEditOpen", function(opts)
  epubedit.open(opts.args)
end, {
  nargs = "?",
  complete = "file",
  desc = "Unpack an EPUB archive into an editable workspace",
})

vim.api.nvim_create_user_command("EpubEditSave", function(opts)
  epubedit.save(opts.args)
end, {
  nargs = "?",
  complete = "file",
  desc = "Repack the active EPUB workspace",
})

vim.api.nvim_create_user_command("EpubEditClose", function()
  epubedit.close()
end, {
  desc = "Close the active EPUB workspace without saving",
})

local auto_group = vim.api.nvim_create_augroup("EpubEditAutoOpen", { clear = true })

vim.api.nvim_create_autocmd("BufReadCmd", {
  group = auto_group,
  pattern = "*.epub",
  callback = function(args)
    local match = args.match or vim.api.nvim_buf_get_name(args.buf)
    local target = vim.fn.fnamemodify(match, ":p")
    if target == "" then
      return
    end
    local stat = vim.loop.fs_stat(target)
    if not stat or stat.type ~= "file" then
      return
    end
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(args.buf) then
        pcall(vim.api.nvim_buf_delete, args.buf, { force = true })
      end
      vim.cmd("silent! EpubEditOpen " .. vim.fn.fnameescape(target))
    end)
  end,
})
