local Config = require("neoconf.config")

local validate = vim.validate
local M = {}
local uv = vim.uv or vim.loop
M.islist = vim.islist or vim.tbl_islist

function M.merge(...)
  local function can_merge(v)
    return type(v) == "table" and (vim.tbl_isempty(v) or not M.islist(v))
  end

  local values = { ... }
  local ret = values[1]
  for i = 2, #values, 1 do
    local value = values[i]
    if can_merge(ret) and can_merge(value) then
      for k, v in pairs(value) do
        ret[k] = M.merge(ret[k], v)
      end
    else
      ret = value
    end
  end
  return ret
end

local nvim_eleven = vim.fn.has("nvim-0.11") == 1
local function tbl_flatten(t)
  --- @diagnostic disable-next-line:deprecated
  return nvim_eleven and vim.iter(t):flatten(math.huge):totable() or vim.tbl_flatten(t)
end
-- see https://github.com/neovim/nvim-lspconfig/blob/8b0f47d851ee5343d38fe194a06ad16b9b9bd086/lua/lspconfig/util.lua#L23C1-L25C4
local function escape_wildcards(path)
  return path:gsub("([%[%]%?%*])", "\\%1")
end
function M.root_pattern(...)
  -- see https://github.com/neovim/nvim-lspconfig/blob/8b0f47d851ee5343d38fe194a06ad16b9b9bd086/lua/lspconfig/util.lua#L28C2-L44C6
  local patterns = tbl_flatten({ ... })
  return function(startpath)
    startpath = M.strip_archive_subpath(startpath)
    for _, pattern in ipairs(patterns) do
      local match = M.search_ancestors(startpath, function(path)
        for _, p in ipairs(vim.fn.glob(table.concat({ escape_wildcards(path), pattern }, "/"), true, true)) do
          if vim.uv.fs_stat(p) then
            return path
          end
        end
      end)

      if match ~= nil then
        return match
      end
    end
  end
end

function M.find_git_ancestor(...)
  return vim.fs.dirname(vim.fs.find(".git", { path = startpath, upward = true })[1])
end

function M.has_lspconfig(server)
  local servers = {}
  for s, config in pairs(vim.lsp.config) do
    if config ~= nil then
      table.insert(servers, s)
    end
  end
  return vim.tbl_contains(servers, server)
end

function M.pick_root_dir(a, b)
  -- prefer the longest path
  return #a > #b and a or b
end

---@param t table
---@param ret? table
function M.flatten(t, ret)
  ret = ret or {}
  for _, v in pairs(t) do
    if type(v) == "table" then
      M.flatten(v, ret)
    else
      ret[#ret + 1] = v
    end
  end
  return ret
end

---@param opts? { local: boolean, global: boolean, autocmd: boolean }
---@return string[]
function M.file_patterns(opts)
  opts = M.merge({ ["local"] = true, ["global"] = true }, opts)
  local ret = {}

  if opts["local"] then
    for _, p in ipairs(Config.local_patterns) do
      table.insert(ret, p.pattern)
    end
  end

  if opts["global"] then
    for _, p in ipairs(Config.global_patterns) do
      table.insert(ret, p.pattern)
    end
  end

  if opts.autocmd then
    for i, v in ipairs(ret) do
      if v:find("/") then
        ret[i] = "*/" .. v
      end
    end
  end

  return vim.tbl_map(vim.fs.normalize, ret)
end

---@return { pattern: table<string, string>, filename: table<string, string> }
function M.filetype_patterns()
  local pattern = {}
  local filename = {}

  for _, p in ipairs(M.file_patterns({ autocmd = true })) do
    if p:find("/") ~= nil then
      pattern[".*/" .. p:gsub("%.", "%."):gsub("%*", ".*")] = "jsonc"
    else
      filename[p] = "jsonc"
    end
  end

  return {
    pattern = pattern,
    filename = filename,
  }
end

function M.path(str)
  local f = debug.getinfo(1, "S").source:sub(2)
  return M.fqn(vim.fn.fnamemodify(f, ":h:h:h") .. "/" .. (str or ""))
end

function M.read_file(file)
  local fd = io.open(file, "r")
  if not fd then
    error(("Could not open file %s for reading"):format(file))
  end
  local data = fd:read("*a")
  fd:close()
  return data
end

function M.write_file(file, data)
  local fd = io.open(file, "w+")
  if not fd then
    error(("Could not open file %s for writing"):format(file))
  end
  fd:write(data)
  fd:close()
end

function M.json_decode(json)
  json = vim.trim(json)
  if json == "" then
    json = "{}"
  end
  return require("neoconf.json.jsonc").decode_jsonc(json)
end

function M.fqn(fname)
  fname = vim.fn.fnamemodify(fname, ":p")
  return uv.fs_realpath(fname) or fname
end

---@param root_dir string
---@param file string
function M.has_file(root_dir, file)
  root_dir = M.fqn(root_dir)
  file = M.fqn(file)
  return M.exists(file) and file:find(root_dir, 1, true) == 1
end

function M.protect(fn, msg)
  return function(...)
    local args = { ... }

    return xpcall(function()
      return fn(unpack(args))
    end, function(err)
      local lines = {}
      if msg then
        table.insert(lines, msg)
      end
      table.insert(lines, err)
      table.insert(lines, debug.traceback("", 3))

      M.error(table.concat(lines, "\n"))
      return err
    end)
  end
end

function M.try(fn, msg)
  M.protect(fn, msg)()
end

function M.config_path()
  return uv.fs_realpath(vim.fn.stdpath("config"))
end

function M.is_nvim_config(path)
  return M.has_file(M.fqn(path), M.config_path())
end

---@param patterns SettingsPattern[]
---@param fn fun(file: string, key:string|nil, pattern:string)
---@param root_dir string
function M.for_each(patterns, fn, root_dir)
  for _, p in ipairs(patterns) do
    local file = root_dir .. "/" .. p.pattern
    ---@diagnostic disable-next-line: param-type-mismatch
    for _, f in pairs(vim.fn.expand(file, false, true)) do
      ---@diagnostic disable-next-line: param-type-mismatch
      fn(f, type(p.key) == "function" and p.key(f) or p.key, p.pattern)
    end
  end
end

---@param patterns string|(string|SettingsPattern)[]
---@return SettingsPattern[]
function M.expand(patterns)
  return vim.tbl_map(function(p)
    return type(p) == "string" and { pattern = p } or p
  end, type(patterns) == "table" and patterns or { patterns })
end

---@param root_dir string
---@param fn fun(file: string, key:string|nil, pattern:string)
function M.for_each_local(fn, root_dir)
  M.for_each(Config.local_patterns, fn, root_dir)
end

---@param fn fun(file: string, key:string|nil, pattern:string)
function M.for_each_global(fn)
  M.for_each(Config.global_patterns, fn, vim.fn.stdpath("config"))
end

function M.is_global(file)
  local ret = false
  M.for_each_global(function(f)
    if file == f then
      ret = true
    end
  end)
  return ret
end

function M.fetch(url)
  local fd = io.popen(string.format("curl -s -k %q", url))
  if not fd then
    error(("Could not download %s"):format(url))
  end
  local ret = fd:read("*a")
  fd:close()
  return ret
end

function M.json_format(obj)
  local tmp = os.tmpname()
  M.write_file(tmp, vim.json.encode(obj))
  local fd = io.popen("jq -S < " .. tmp)
  if not fd then
    error("Could not format json")
  end
  local ret = fd:read("*a")
  if ret == "" then
    error("Could not format json")
  end
  fd:close()
  return ret
end

function M.mtime(fname)
  local stat = uv.fs_stat(fname)
  return (stat and stat.type) and stat.mtime.sec or 0
end

function M.exists(fname)
  local stat = uv.fs_stat(fname)
  return (stat and stat.type) or false
end

function M.notify(msg, level)
  vim.notify(msg, level, {
    title = "settings.nvim",
    on_open = function(win)
      vim.api.nvim_set_option_value("conceallevel", 3, {
        win = win,
        scope = "local",
      })
      local buf = vim.api.nvim_win_get_buf(win)
      vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf, scope = "local" })
      vim.api.nvim_set_option_value("spell", false, { buf = buf, scope = "local" })
    end,
  })
end

function M.warn(msg)
  M.notify(msg, vim.log.levels.WARN)
end

function M.error(msg)
  M.notify(msg, vim.log.levels.ERROR)
end

function M.info(msg)
  M.notify(msg, vim.log.levels.INFO)
end
-- For zipfile: or tarfile: virtual paths, returns the path to the archive.
-- Other paths are returned unaltered.
function M.strip_archive_subpath(path)
  -- Matches regex from zip.vim / tar.vim
  path = vim.fn.substitute(path, "zipfile://\\(.\\{-}\\)::[^\\\\].*$", "\\1", "")
  path = vim.fn.substitute(path, "tarfile:\\(.\\{-}\\)::.*$", "\\1", "")
  return path
end

---
---
---
--- Deprecated: Remove these functions when we drop support for legacy configs:
---
---
---

--- Deprecated in Nvim 0.11
function M.search_ancestors(startpath, func)
  if nvim_eleven then
    validate("func", func, "function")
  end
  if func(startpath) then
    return startpath
  end
  local guard = 100
  for path in vim.fs.parents(startpath) do
    -- Prevent infinite recursion if our algorithm breaks
    guard = guard - 1
    if guard == 0 then
      return
    end

    if func(path) then
      return path
    end
  end
end

return M
