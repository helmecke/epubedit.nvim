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

vim.api.nvim_create_user_command("EpubEditSpine", function()
  epubedit.spine()
end, {
  desc = "Open the spine editor to manage reading order",
})

vim.api.nvim_create_user_command("EpubEditPreview", function()
  epubedit.preview()
end, {
  desc = "Open the current EPUB file in a web browser for preview",
})

vim.api.nvim_create_user_command("EpubEditToc", function()
  epubedit.toc()
end, {
  desc = "Open the table of contents editor for the active EPUB",
})

vim.api.nvim_create_user_command("EpubEditTocGenerate", function()
  epubedit.toc_generate()
end, {
  desc = "Generate table of contents from document headings (h1-h6)",
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

-- Cleanup resources on Neovim exit
local cleanup_group = vim.api.nvim_create_augroup("EpubEditCleanup", { clear = true })

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = cleanup_group,
  callback = function()
    -- Stop the preview server if running
    local server = require("epubedit.server")
    if server.is_running() then
      server.stop()
    end

    -- Clean up all active sessions
    local module = require("epubedit.module")
    if module.state.current then
      module.cleanup()
    end
  end,
})
