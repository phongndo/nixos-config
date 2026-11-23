vim.g.mapleader = " "
vim.g.maplocalleader = " "

local opt = vim.opt
opt.number = true
opt.relativenumber = true
opt.signcolumn = "yes" -- keep diagnostics from shifting the text
opt.termguicolors = true
opt.wrap = false
opt.scrolloff = 8
opt.clipboard = "unnamedplus"
opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.ignorecase = true
opt.smartcase = true
opt.undofile = true
opt.updatetime = 250 -- CursorHold, used below to reload files agents change
opt.splitbelow = true
opt.splitright = true
opt.wildoptions = "pum,fuzzy"
opt.wildmode = "noselect:lastused,full"
opt.winborder = "rounded" -- outlines transparent popups (hover, pickers, diagnostics)

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  local out = vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
  if vim.v.shell_error ~= 0 then
    error("lazy.nvim install failed:\n" .. out)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  {
    "projekt0n/github-nvim-theme",
    name = "github-theme",
    lazy = false,
    priority = 1000,
    config = function()
      -- The terminal's background shows through the editor and popups alike,
      -- including the native popup (e.g. :buffer suggestions).
      local clear = { bg = "NONE" }
      require("github-theme").setup({
        options = { transparent = true, darken_floats = false },
        groups = {
          github_dark_high_contrast = {
            NormalFloat = clear,
            FloatBorder = clear,
            Pmenu = clear,
            PmenuKind = clear,
            PmenuExtra = clear,
            PmenuSbar = clear,
          },
        },
      })
      vim.cmd.colorscheme("github_dark_high_contrast")
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false, -- the main branch doesn't support lazy-loading
    build = ":TSUpdate",
    config = function()
      -- Installs any that are missing, in the background. Neovim already
      -- bundles c, lua, markdown, query, vim and vimdoc.
      require("nvim-treesitter").install({
        "bash",
        "cpp",
        "css",
        "diff",
        "javascript",
        "json",
        "llvm", -- LLVM IR (.ll)
        "markdown_inline",
        "mlir",
        "nix",
        "python",
        "rust",
        "tablegen", -- LLVM TableGen (.td)
        "toml",
        "tsx",
        "typescript",
        "yaml",
        "zig",
      })
    end,
  },
  {
    -- Only supplies server definitions (lsp/*.lua); setup is below.
    "neovim/nvim-lspconfig",
    lazy = false,
  },
  {
    -- The menu opens as you type with nothing selected: <C-n>/<C-p> select,
    -- <CR> accepts the selection (or is a plain newline), <C-e> closes it.
    "saghen/blink.cmp",
    version = "1.*",
    lazy = false, -- it advertises its LSP capabilities before any server starts
    opts = function()
      local function open(cmp)
        return cmp.show({ initial_selected_item_idx = 1 })
      end
      return {
        keymap = {
          preset = "none",
          ["<C-n>"] = { "select_next", open, "fallback" },
          ["<C-p>"] = { "select_prev", open, "fallback" },
          ["<CR>"] = { "accept", "fallback" },
          ["<C-e>"] = { "hide", "fallback" },
          ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
          ["<C-b>"] = { "scroll_documentation_up", "fallback" },
          ["<C-f>"] = { "scroll_documentation_down", "fallback" },
          -- Jump between a completed function's argument placeholders.
          ["<Tab>"] = { "snippet_forward", "fallback" },
          ["<S-Tab>"] = { "snippet_backward", "fallback" },
        },
        completion = {
          menu = { auto_show = true },
          list = { selection = { preselect = false, auto_insert = false } },
          documentation = { auto_show = true },
          ghost_text = { enabled = false },
        },
        signature = { enabled = false }, -- Neovim's <C-s> shows it on demand
        cmdline = { enabled = false },
        sources = { default = { "lsp", "path", "buffer" } },
        -- No downloaded native binary or Rust build needed on either Nix host.
        fuzzy = { implementation = "lua" },
      }
    end,
  },
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = function()
      -- The colours come from the colorscheme, but only the mode pill gets a
      -- background; the rest of the bar lets the terminal show through.
      local theme = require("lualine.themes.auto")
      for _, mode in pairs(theme) do
        for name, section in pairs(mode) do
          if name ~= "a" then
            section.bg = "NONE"
          end
        end
      end
      return {
        options = {
          theme = theme,
          globalstatus = true,
          component_separators = "",
          section_separators = "",
        },
        sections = {
          -- No fileformat: its icon is the line-ending style (Tux for LF),
          -- not the OS. Encoding shows only when it isn't the usual UTF-8.
          lualine_x = {
            {
              "encoding",
              cond = function()
                local enc = vim.bo.fileencoding
                return enc ~= "" and enc ~= "utf-8"
              end,
            },
            "filetype",
          },
        },
      }
    end,
  },
  {
    "dmtrKovalenko/fff",
    lazy = false, -- fff initialises itself on first use
    build = function(plugin)
      -- CI skips release binaries for some commits, and fff's cargo fallback
      -- needs rustup, which z doesn't have, so build those with its flake.
      if pcall(require("fff.download").download_or_build_binary) then
        return
      end
      local out = vim.system({ "nix", "run", ".#release" }, { cwd = plugin.dir }):wait()
      if out.code ~= 0 then
        error("fff build failed:\n" .. out.stderr)
      end
    end,
    keys = {
      { "<leader>f", function() require("fff").find_files() end, desc = "Find files" },
      { "<leader>/", function() require("fff").live_grep({ title = "live grep" }) end, desc = "Live grep" },
      {
        "<leader>*",
        function() require("fff").live_grep_under_cursor({ title = "live grep" }) end,
        mode = { "n", "x" },
        desc = "Grep word or selection",
      },
    },
    opts = { prompt = "", title = "files" },
  },
  {
    "stevearc/oil.nvim",
    lazy = false,
    keys = { { "-", "<cmd>Oil<cr>", desc = "Open parent directory" } },
    opts = {},
  },
  {
    -- Buffers, which fff doesn't pick. Only the picker is enabled; it loads on
    -- first use.
    "folke/snacks.nvim",
    keys = {
      { "<leader>,", function() require("snacks").picker.buffers() end, desc = "Buffers" },
    },
    opts = function()
      -- Mirror fff's picker: one rounded frame at 80% of the screen, the
      -- prompt along the bottom with the best match just above it, and the
      -- preview beside the list, or above it below 130 columns.
      local list_and_input = {
        box = "vertical",
        { win = "list", border = "none" },
        { win = "input", height = 1, border = "top" },
      }
      local frame = {
        width = 0.8,
        height = 0.8,
        border = "rounded",
        title = "{title} {live} {flags}",
        title_pos = "left",
      }
      return {
        picker = {
          enabled = true,
          -- Rows and prompt as fff draws them: "name dir", no prompt icon.
          prompt = "",
          formatters = { file = { filename_first = true } },
          icons = { files = { enabled = false } },
          sources = {
            buffers = {
              title = "buffers",
              format = "file",
              -- Drop the ":line" suffix; switching restores the cursor anyway.
              transform = function(item)
                item.pos = nil
              end,
            },
          },
          layouts = {
            fff = {
              reverse = true,
              layout = vim.tbl_extend("force", frame, {
                box = "horizontal",
                list_and_input,
                { win = "preview", title = "{preview}", width = 0.5, border = "left" },
              }),
            },
            fff_narrow = {
              reverse = true,
              layout = vim.tbl_extend("force", frame, {
                box = "vertical",
                { win = "preview", title = "{preview}", height = 0.5, border = "bottom" },
                list_and_input,
              }),
            },
          },
          layout = {
            preset = function()
              return vim.o.columns >= 130 and "fff" or "fff_narrow"
            end,
          },
        },
      }
    end,
  },
}, {
  -- This file is a read-only link into the Nix store, so there are no edits to
  -- watch for, and no plugin here needs luarocks.
  change_detection = { enabled = false },
  rocks = { enabled = false },
})
vim.keymap.set("n", "<leader>l", "<cmd>Lazy<cr>", { desc = "Lazy (plugins)" })

-- Syntax highlighting: treesitter for every filetype with an installed parser.
vim.api.nvim_create_autocmd("FileType", {
  callback = function(args)
    pcall(vim.treesitter.start, args.buf)
  end,
})

-- Language servers. Each starts only if its executable is on PATH, so open
-- Neovim inside the project (direnv) to use the toolchain-matched servers its
-- development shell provides; home/packages.nix covers the rest. Keep compiler
-- flags, Python environments, etc. in project configuration. Neovim also maps
-- K (hover), [d / ]d (diagnostics), gO (symbols), <C-s> (signature help in
-- Insert mode) and gq (format).
vim.lsp.config("nixd", {
  settings = {
    nixd = { formatting = { command = { "nixfmt" } } },
  },
})
-- The project's .venv (uv and friends), not whichever python is on PATH.
vim.lsp.config("pyright", {
  before_init = function(_, config)
    local venv = vim.fs.find(".venv", { path = config.root_dir, upward = true, type = "directory" })[1]
    if venv then
      config.settings.python = config.settings.python or {}
      config.settings.python.pythonPath = venv .. "/bin/python"
    end
  end,
})
-- Neovim's Lua API for config and plugin code; a project's .luarc.json wins.
vim.lsp.config("lua_ls", {
  on_init = function(client)
    local root = client.workspace_folders and client.workspace_folders[1].name
    if root and (vim.uv.fs_stat(root .. "/.luarc.json") or vim.uv.fs_stat(root .. "/.luarc.jsonc")) then
      return
    end
    client.config.settings.Lua = vim.tbl_deep_extend("force", client.config.settings.Lua, {
      runtime = { version = "LuaJIT", path = { "lua/?.lua", "lua/?/init.lua" } },
      workspace = { checkThirdParty = false, library = { vim.env.VIMRUNTIME } },
    })
  end,
  settings = { Lua = {} },
})
vim.lsp.enable({
  -- C / C++: whichever clangd is on PATH, using the project's
  -- compile_commands.json. LLVM and other Nix shells provide one matched to
  -- their compiler; elsewhere on the Mac it's Xcode's. Don't force a sysroot in
  -- ~/Library/Preferences/clangd/config.yaml: it overrides those shells' SDKs.
  "clangd",
  "rust_analyzer",
  "ts_ls", -- JavaScript / TypeScript, including React JSX / TSX.
  "pyright",
  "lua_ls",
  "nixd",
  "bashls",
  "jsonls",
  "cssls",
  -- Only from a project's shell or an LLVM build with MLIR:
  "mlir_lsp_server",
  "tblgen_lsp_server",
  "zls",
})

-- Diagnostics: signs and underlines everywhere, the message only on the
-- cursor's line. Neovim maps ]d / [d (next / previous), ]D / [D (last /
-- first) and <C-w>d (full message in a float).
vim.diagnostic.config({
  virtual_text = { current_line = true },
  severity_sort = true,
  float = { source = "if_many" },
})
vim.keymap.set("n", "<leader>q", function()
  if vim.fn.getqflist({ winid = 0 }).winid ~= 0 then
    vim.cmd.cclose()
  else
    vim.diagnostic.setqflist()
  end
end, { desc = "Toggle all diagnostics in quickfix" })

-- Neovim maps the rest of LSP: grn rename, gra code action, grr references,
-- gri implementation, grt type definition, gO symbols, K hover, <C-s>
-- signature help (Insert mode), <C-]> definition and gq format.
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = args.buf, desc = "Go to definition" })
    vim.keymap.set("n", "gD", vim.lsp.buf.declaration, { buffer = args.buf, desc = "Go to declaration" })
  end,
})

-- Working alongside agents: pick up their edits to open files, and copy a
-- file:line (or file:start-end) reference to paste into a prompt.
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  command = "silent! checktime",
})
vim.keymap.set({ "n", "x" }, "<leader>y", function()
  local first, last = vim.fn.line("v"), vim.fn.line(".")
  if first > last then
    first, last = last, first
  end
  local ref = vim.fn.expand("%:.") .. ":" .. first .. (first ~= last and "-" .. last or "")
  vim.fn.setreg("+", ref)
  vim.notify("Copied " .. ref)
end, { desc = "Copy file:line reference" })
