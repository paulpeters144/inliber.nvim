local filter = require("inliber.tools.helpers.filter")
local log = require("inliber.utils.log")

---@class Inliber.Tools.Filter
local Filter = filter.create_filter({
  skip_keys = { "opts", "groups" },
  post_filter = function(filtered_cfg, opts)
    -- Adapter specific tools
    if opts and opts.adapter and opts.adapter.available_tools then
      for name, cfg in pairs(opts.adapter.available_tools) do
        local should_show = true
        if cfg.enabled ~= nil then
          if type(cfg.enabled) == "function" then
            should_show = cfg.enabled(opts.adapter)
          else
            should_show = cfg.enabled
          end
        end

        -- An adapter's tool will take precedence over built-in tools
        if should_show then
          filtered_cfg[name] = vim.tbl_extend("force", cfg, {
            _adapter_tool = true,
            _has_client_tool = cfg.opts and cfg.opts.client_tool and true or false,
          })
        end
      end
    end

    -- Filter tool groups to only include enabled ones
    if filtered_cfg.groups then
      for name, cfg in pairs(filtered_cfg.groups) do
        if cfg.tools then
          local enabled_group_tools = {}
          for _, tool_name in ipairs(cfg.tools) do
            if opts.enabled_items[tool_name] then
              table.insert(enabled_group_tools, tool_name)
            end
          end
          filtered_cfg.groups[name].tools = enabled_group_tools

          if #enabled_group_tools == 0 then
            filtered_cfg.groups[name] = nil
            log:trace("[Tool Filter] Filtered out group with no enabled tools: %s", name)
          end
        end
      end
    end

    return filtered_cfg
  end,
})

-- Maintain backward compatibility with existing API
Filter.filter_enabled_tools = Filter.filter_enabled

return Filter
