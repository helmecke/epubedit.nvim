local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local d = ls.dynamic_node
local sn = ls.snippet_node

return {
  s("img+", {
    t('<img src="../Images/'),
    i(1, "filename.jpg"),
    t('" alt="'),
    i(2, "description"),
    t('" id="'),
    f(function(args)
      local filename = args[1][1]:gsub("%..*$", "")
      return "img_" .. filename
    end, { 1 }),
    t('" />'),
  }),

  s("section+", {
    t('<section epub:type="'),
    i(1, "chapter"),
    t('" id="'),
    f(function(args)
      local section_type = args[1][1]
      return "sec_" .. section_type .. "_" .. os.time()
    end, { 1 }),
    t({ '">',

 "  <h" }),
    i(2, "2"),
    t({ ">" }),
    i(3, "Section Title"),
    t({ "</h" }),
    f(function(args)
      return args[1][1]
    end, { 2 }),
    t({ ">", "  " }),
    i(0),
    t({ "", "</section>" }),
  }),

  s("chapter+", {
    t({ '<?xml version="1.0" encoding="utf-8"?>', '<!DOCTYPE html>' }),
    t({ '',
      '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">' }),
    t({ "", "<head>" }),
    t({ "", "  <title>" }),
    i(1, "Chapter Title"),
    t({ "</title>" }),
    t({ "", '  <link href="../Styles/' }),
    i(2, "stylesheet"),
    t({ '.css" rel="stylesheet" type="text/css" />' }),
    t({ "", "</head>", "<body>", '  <section epub:type="chapter" id="' }),
    f(function()
      local filename = vim.fn.expand("%:t:r")
      return "ch_" .. filename
    end),
    t({ '">', "    <h1>" }),
    f(function(args)
      return args[1][1]
    end, { 1 }),
    t({ "</h1>", "    " }),
    i(0),
    t({ "", "  </section>", "</body>", "</html>" }),
  }),

  s("date", {
    f(function()
      return os.date("%Y-%m-%d")
    end),
  }),

  s("timestamp", {
    f(function()
      return os.date("%Y-%m-%d %H:%M:%S")
    end),
  }),

  s("meta", {
    t('<meta name="'),
    i(1, "generator"),
    t('" content="'),
    c(2, {
      t("epubedit.nvim"),
      f(function()
        return "epubedit.nvim " .. os.date("%Y-%m-%d")
      end),
      i(nil, "custom content"),
    }),
    t('" />'),
  }),

  s("figure", {
    t({ '<figure id="' }),
    f(function(args)
      local filename = args[1][1]:gsub("%..*$", "")
      return "fig_" .. filename
    end, { 1 }),
    t({ '">', '  <img src="../Images/' }),
    i(1, "image.jpg"),
    t('" alt="'),
    i(2, "description"),
    t({ '" />', "  <figcaption>" }),
    i(3, "Caption"),
    t({ "</figcaption>", "</figure>" }),
    i(0),
  }),

  s("aside+", {
    t('<aside epub:type="'),
    c(1, {
      t("sidebar"),
      t("note"),
      t("warning"),
      t("tip"),
      t("footnote"),
    }),
    t('" id="'),
    f(function(args)
      local aside_type = args[1][1]
      return aside_type .. "_" .. os.time()
    end, { 1 }),
    t({ '">', "  <p>" }),
    i(2, "Content"),
    t({ "</p>", "</aside>" }),
    i(0),
  }),

  s("alink+", {
    t('<a href="'),
    i(1, "chapter.xhtml"),
    t('#'),
    i(2, "anchor"),
    t('" id="'),
    f(function(args)
      local target = args[1][1]:gsub("%.xhtml$", "")
      local anchor = args[2][1]
      return "link_" .. target .. "_" .. anchor
    end, { 1, 2 }),
    t('">'),
    i(3, "link text"),
    t("</a>"),
    i(0),
  }),

  s("table+", {
    t({ '<table id="' }),
    f(function()
      return "table_" .. os.time()
    end),
    t({ '">', "  <thead>", "    <tr>", "      <th>" }),
    i(1, "Header 1"),
    t("</th>"),
    t({ "", "      <th>" }),
    i(2, "Header 2"),
    t({ "</th>", "    </tr>", "  </thead>", "  <tbody>", "    <tr>", "      <td>" }),
    i(3, "Cell 1"),
    t("</td>"),
    t({ "", "      <td>" }),
    i(4, "Cell 2"),
    t({ "</td>", "    </tr>", "  </tbody>", "</table>" }),
    i(0),
  }),
}
