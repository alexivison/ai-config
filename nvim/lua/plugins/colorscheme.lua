return {
  {
    "projekt0n/github-nvim-theme",
    name = "github-theme",
    config = function()
      require("github-theme").setup({
        options = {
          transparent = true,
          darken = {
            floats = false,
            sidebars = { enable = false },
          },
        },
        groups = {
          github_dark_dimmed = {
            Directory = { fg = "#6cb6ff" },
          },
        },
      })
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "github_dark_dimmed",
    },
  },
}
