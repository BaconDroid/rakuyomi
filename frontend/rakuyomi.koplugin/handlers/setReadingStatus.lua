local StatusPickerDialog = require("StatusPickerDialog")

--- @param manga Manga
local function setReadingStatus(manga)
  StatusPickerDialog:fetchAndShow(manga)
end

return setReadingStatus
