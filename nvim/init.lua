vim.g.mapleader = " "
vim.g.maplocalleader = " "

local opt = vim.opt
opt.number = true
opt.relativenumber = true
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
opt.splitbelow = true
opt.splitright = true

vim.diagnostic.config({
  virtual_text = false,
  virtual_lines = false,
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
  float = { border = "rounded", source = "if_many" },
})

vim.keymap.set("n", "<leader>d", vim.diagnostic.open_float, { desc = "Line diagnostics" })
vim.keymap.set("n", "<leader>q", vim.diagnostic.setqflist, { desc = "All diagnostics" })

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLsp", { clear = true }),
  callback = function(args)
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = args.buf, desc = "Go to definition" })
    -- Don't wait for Neovim's longer gr-prefixed mappings.
    vim.keymap.set("n", "gr", vim.lsp.buf.references, { buffer = args.buf, nowait = true, desc = "References" })
    vim.keymap.set("n", "gi", vim.lsp.buf.implementation, { buffer = args.buf, desc = "Go to implementation" })
    vim.keymap.set("n", "<leader>r", vim.lsp.buf.rename, { buffer = args.buf, desc = "Rename" })
    vim.keymap.set({ "n", "x" }, "<leader>a", vim.lsp.buf.code_action, { buffer = args.buf, desc = "Code action" })
    -- Keep Neovim's K (hover) and [d / ]d (diagnostic navigation).
  end,
})

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
    "neovim/nvim-lspconfig",
    lazy = false,
    dependencies = { "saghen/blink.cmp" },
    config = function()
      vim.lsp.config("*", {
        capabilities = require("blink.cmp").get_lsp_capabilities(),
      })
      vim.lsp.config("nixd", {
        settings = {
          nixd = { formatting = { command = { "nixfmt" } } },
        },
      })

      -- Executables come from home/packages.nix or the project's development shell.
      -- Keep compiler flags, Python environments, etc. in project configuration.
      vim.lsp.enable({
        "clangd", -- C / C++; use the project's compile_commands.json.
        "pyright",
        "rust_analyzer",
        "zls",
        "ocamllsp",
        "ts_ls", -- JavaScript / TypeScript, including React JSX / TSX.
        "bashls",
        "cssls",
        "html",
        "jsonls",
        "yamlls",
        "nixd",
      })
    end,
  },
  {
    "saghen/blink.cmp",
    version = "1.*",
    opts = {
      keymap = { preset = "enter" },
      completion = {
        list = { selection = { preselect = false, auto_insert = false } },
        documentation = { auto_show = false },
        ghost_text = { enabled = false },
      },
      signature = { enabled = false },
      cmdline = { enabled = false },
      sources = { default = { "lsp", "path", "buffer" } },
      -- No downloaded native binary or Rust build needed on either Nix host.
      fuzzy = { implementation = "lua" },
    },
  },
  {
    "phongndo/origin.nvim",
    lazy = false,
    priority = 1000,
    opts = { transparent = true },
    config = function(_, opts)
      require("origin").setup(opts)
      vim.cmd.colorscheme("origin")
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    event = { "BufReadPost", "BufNewFile" },
    build = ":TSUpdate",
  },
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = {
      options = {
        theme = "auto",
        globalstatus = true,
        component_separators = "",
        section_separators = "",
      },
    },
  },
  {
    "folke/snacks.nvim",
    keys = {
      { "<leader>f", function() require("snacks").picker.files() end, desc = "Find files" },
      { "<leader>/", function() require("snacks").picker.grep() end, desc = "Live grep" },
      { "<leader>,", function() require("snacks").picker.buffers() end, desc = "Buffers" },
    },
    opts = { picker = { enabled = true } },
  },
  {
    "stevearc/oil.nvim",
    lazy = false,
    keys = { { "-", "<cmd>Oil<cr>", desc = "Open parent directory" } },
    opts = {},
  },
})

vim.api.nvim_create_autocmd("FileType", {
  callback = function(args)
    pcall(vim.treesitter.start, args.buf)
  end,
})
