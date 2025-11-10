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

vim.api.nvim_create_user_command("EpubEditCheck", function()
  epubedit.check()
end, {
  desc = "Validate the active EPUB workspace with epubcheck/xmllint",
})

vim.api.nvim_create_user_command("EpubEditMetadata", function()
  epubedit.metadata()
end, {
  desc = "Open the metadata editor for the active EPUB",
})

local auto_group = vim.api.nvim_create_augroup("EpubEditAutoOpen", { clear = true })

vim.api.nvim_create_autocmd("BufReadCmd", {
  group = auto_group,
  pattern = "*.epub",
  callback = function(args)
    local match = args.match or vim.api.nvim_buf_get_name(args.buf)
    epubedit._auto_open(match, args.buf)
  end,
})
