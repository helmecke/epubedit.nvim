local function ensure_repo(path, url)
  if vim.fn.isdirectory(path) == 0 then
    vim.fn.system({ "git", "clone", "--depth=1", url, path })
  end
end

local plenary_dir = os.getenv("PLENARY_DIR") or "/tmp/plenary.nvim"
ensure_repo(plenary_dir, "https://github.com/nvim-lua/plenary.nvim")

local nui_dir = os.getenv("NUI_DIR") or "/tmp/nui.nvim"
ensure_repo(nui_dir, "https://github.com/MunifTanjim/nui.nvim")

local neotree_dir = os.getenv("NEOTREE_DIR") or "/tmp/neo-tree.nvim"
ensure_repo(neotree_dir, "https://github.com/nvim-neo-tree/neo-tree.nvim")

vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_dir)
vim.opt.rtp:append(nui_dir)
vim.opt.rtp:append(neotree_dir)

vim.cmd("runtime plugin/plenary.vim")
require("plenary.busted")
