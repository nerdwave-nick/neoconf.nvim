local M = {}

---@class Config
M.defaults = {
  -- name of the local settings files
  local_settings = ".neoconf.json",
  -- name of the global settings file in your Neovim config directory
  global_settings = "neoconf.json",
  -- set the filetype to jsonc for settings files, so you can use comments
  -- make sure you have the jsonc treesitter parser installed!
  filetype_jsonc = true,
}

--- @type Config
M.options = {}

---@class SettingsPattern
---@field pattern string
---@field key? string|fun(string):string

---@type SettingsPattern[]
M.local_patterns = {}

---@type SettingsPattern[]
M.global_patterns = {}

function M.setup(options)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, options or {})

  local util = require("neoconf.util")

  M.local_patterns = {}
  M.global_patterns = {}

  require("neoconf.import").setup()

  vim.list_extend(M.local_patterns, util.expand(M.options.local_settings))
  vim.list_extend(M.global_patterns, util.expand(M.options.global_settings))
end

---@return Config
function M.merge(options)
  return vim.tbl_deep_extend("force", {}, M.options, options or {})
end

function M.get(opts)
  return require("neoconf").get("neoconf", M.options, opts)
end

return M
