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
