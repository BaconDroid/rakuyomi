local CustomDialog = require("CustomDialog")
local MenuItem = require("MenuItem")
local ButtonWidget = require("ui/widget/button")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local GestureRange = require("ui/gesturerange")
local Font = require("ui/font")
local Size = require("ui/size")
local Geom = require("ui/geometry")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local UIManager = require("ui/uimanager")
local Trapper = require("ui/trapper")
local _ = require("gettext+")
local Icons = require("Icons")

local Backend = require("Backend")
local ErrorDialog = require("ErrorDialog")
local InfoMessage = require("ui/widget/infomessage")

local Screen = Device.screen

--- A MenuItem subclass that dispatches taps to a plain callback instead of
--- requiring a Menu parent object.
local StatusItem = MenuItem:extend {
  on_tap = nil,  -- fun(): nil
  status = nil,  -- ReadingStatus
}

function StatusItem:init()
  self.ges_events = {
    TapSelect = {
      GestureRange:new {
        ges = "tap",
        range = self.dimen,
      },
    },
    Pan = { -- (for mousewheel scrolling support)
      GestureRange:new {
        ges = "pan",
        range = self.dimen,
      }
    },
  }

  local face = Font:getFace(self.font)
  self.content_width = self.dimen.w - 2 * Size.padding.fullscreen

  ---@type ReadingStatus
  local status = self.status
  self._underline_container = UnderlineContainer:new {
    color = self.line_color,
    linesize = self.linesize,
    vertical_align = "center",
    padding = 0,
    dimen = Geom:new {
      x = 0, y = 0,
      w = self.content_width,
      h = self.dimen.h
    },
    HorizontalGroup:new {
      align = "center",
      OverlapGroup:new {
        dimen = Geom:new { w = self.content_width, h = self.dimen.h },
        LeftContainer:new {
          dimen = Geom:new { w = self.content_width, h = self.dimen.h },
          TextWidget:new {
            text = status.name,
            face = face,
            max_width = self.content_width,
          },
        },
      }
    },
  }

  self[1] = self._underline_container
end

function StatusItem:onTapSelect()
  if self.on_tap then self.on_tap() end
  return true
end

--- @class StatusPickerDialog: CustomDialog
---@diagnostic disable-next-line: redundant-parameter
local StatusPickerDialog = CustomDialog:extend {}

--- Shows the status picker dialog.
--- @param manga Manga The manga to assign a reading status to.
function StatusPickerDialog:fetchAndShow(manga)
  Trapper:wrap(function()
    local response = Backend.getReadingStatuses()
    if response.type == 'ERROR' then
      ErrorDialog:show(response.message)
      return
    end
    StatusPickerDialog:_buildAndShow(response.body, manga)
  end)
end

--- @private
function StatusPickerDialog:_buildAndShow(statuses, manga)
  local current_dialog

  local function on_select_status(status)
    if current_dialog then UIManager:close(current_dialog) end
    Trapper:wrap(function()
      local r = Backend.setMangaStatus(manga.source.id, manga.id, status.id)
      if r.type == 'ERROR' then
        ErrorDialog:show(r.message)
        return
      end
      UIManager:show(InfoMessage:new {
        text = _("Status set to") .. " \"" .. status.name .. "\""
      })
    end)
  end

  local function on_remove_status()
    if current_dialog then UIManager:close(current_dialog) end
    Trapper:wrap(function()
      local r = Backend.removeMangaStatus(manga.source.id, manga.id)
      if r.type == 'ERROR' then
        ErrorDialog:show(r.message)
        return
      end
      UIManager:show(InfoMessage:new {
        text = _("Status removed")
      })
    end)
  end

  -- Build options list
  local options = {}
  table.insert(options, { _type = "remove_status" })

  if #statuses == 0 then
    table.insert(options, { _type = "empty" })
  else
    for _, s in ipairs(statuses) do
      table.insert(options, { _type = "status", status = s })
    end
  end

  local item_height = Screen:scaleBySize(50)

  ---@diagnostic disable-next-line: undefined-field
  current_dialog = StatusPickerDialog:new {
    title = _("Reading Status"),
    options = options,
    generate = function(option, max_width, _index)
      if option._type == "remove_status" then
        -- "Remove status" button at the top
        local btn = ButtonWidget:new {
          text = Icons.FA_TRASH .. "  " .. _("Remove status"),
          face = Font:getFace("smallffont"),
          radius = Size.radius.button,
          bordersize = Size.border.button,
          padding = Size.padding.button,
          width = max_width - Size.padding.button * 2,
          callback = on_remove_status,
        }
        btn.dimen = btn:getSize()
        return btn
      elseif option._type == "empty" then
        local tw = TextWidget:new {
          text = _("No statuses available."),
          face = Font:getFace("smallffont"),
          fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        }
        tw.dimen = tw:getSize()
        return tw
      else
        -- Proper MenuItem-style row with tap to assign the status
        local s = option.status
        local item = StatusItem:new {
          status = s,
          width = max_width,
          dimen = Geom:new {
            x = 0, y = 0,
            w = max_width,
            h = item_height,
          },
          on_tap = function() on_select_status(s) end,
        }
        return item
      end
    end,
  }

  UIManager:show(current_dialog)
end

return StatusPickerDialog
