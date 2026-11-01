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
