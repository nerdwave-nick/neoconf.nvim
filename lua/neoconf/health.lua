local M = {}

local health_start = vim.health.start or vim.health.report_start
local health_ok = vim.health.ok or vim.health.report_ok
local health_warn = vim.health.warn or vim.health.report_warn

function M.check()
  health_start("neoconf.nvim")

  local function ok(msg, ...)
    health_ok(msg:format(...))
  end

  local function warn(msg, ...)
    health_warn(msg:format(...))
  end

  if pcall(vim.treesitter.get_string_parser, "", "jsonc") then
    ok("**jsonc** parser for tree-sitter is installed")
  else
    warn("**jsonc** parser for tree-sitter is not installed. Jsonc highlighting might be broken")
  end

  if pcall(require, "neodev") then
    warn("**neodev.nvim** is installed. lazydev.nvim is a much faster and better replacement for neodev")
  end

  if pcall(require, "lazydev") then
    ok("**lazydev.nvim** is installed")
  else
    warn("**lazydev.nvim** is not installed. You won't get any proper completion for your Neovim config.")
  end
end

function M.check_setup()
  local util = require("neoconf.util")
  if vim.fn.has("nvim-0.7.2") == 0 then
    util.error("**neoconf.nvim** requires Neovim >= 0.7.2")
    return false
  end
  return true
end

return M
