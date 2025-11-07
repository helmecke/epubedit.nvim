if package.preload["neo-tree.sources.epubedit"] == nil then
  package.preload["neo-tree.sources.epubedit"] = function()
    local mod = require("epubedit.neo_tree")
    package.loaded["neo-tree.sources.epubedit"] = mod
    return mod
  end
end
