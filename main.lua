local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local docsettings = require("frontend/docsettings")
local util = require("util")
local _ = require("gettext")

local NotionSync = WidgetContainer:extend{ name = "notionkosync", is_doc_only = true }

function NotionSync:init() self.ui.menu:registerToMainMenu(self) end

function NotionSync:addToMainMenu(menu_items)
    menu_items.notion_sync_plugin = {
        text = _("Notion KoReader Sync"),
        sorting_hint = "tools",
        sub_item_table = {
            { text = _("Sync Highlights & Progress"), callback = function() self:runSync() end },
            { text = _("Reset Book/Log Link"), callback = function() self:resetMapping() end },
        }
    }
end

function NotionSync:extractAnnotations(doc)
    local ds = docsettings:open(doc.file)
    if ds and type(ds.flush) == "function" then pcall(function() ds:flush() end) end
    local raw = ds and ds:readSetting("annotations") or ds:readSetting("bookmarks") or {}
    local annotations = {}
    for _, ann in ipairs(raw) do
        if ann.text and ann.text ~= "" then table.insert(annotations, ann) end
    end
    if ds and ds.close then ds:close() end
    return annotations
end

function NotionSync:runSync()
    local config = require("config")
    local notion = require("notion")
    local doc = self.ui.document
    local ui = self.ui
    local annotations = self:extractAnnotations(doc)
    
    -- PROGRESS LOGIC
    local current_page = 0
    local total_pages = doc:getPageCount() or 0
    local ds = docsettings:open(doc.file)
    local percent_finished = ds:readSetting("percent_finished") or 0
    if ds.close then ds:close() end
    if percent_finished == 0 and ui.paging then
        percent_finished = ui.paging:getPercentFinished() or 0
    end
    current_page = math.floor(percent_finished * total_pages)
    if current_page == 0 and percent_finished > 0 then current_page = 1 end

    local m5 = util.partialMD5(doc.file)
    local book_key = "not_book_" .. m5
    local log_key = "not_log_" .. m5
    
    local saved_book_id = G_reader_settings:readSetting(book_key)
    local saved_log_id = G_reader_settings:readSetting(log_key)

    if saved_book_id and saved_log_id then
        self:executeFinalSync(config, notion, saved_book_id, saved_log_id, annotations, current_page, total_pages)
    else
        -- NEW: Get Clean Metadata without parsing
        local props = doc:getProps()
        local search_title = props.title or doc.file:match("([^/]+)$"):gsub("%.%w+$", "")
        
        -- Remove common artifacts like " (Original 1937 Edition)" for better searching
        search_title = search_title:match("^([^:(]+)") or search_title
        search_title = util.trim(search_title)

        UIManager:show(InfoMessage:new{ text = _("Searching Notion for:\n" .. search_title), timeout = 2 })
        
        UIManager:scheduleIn(0.5, function()
            local ok_b, books = notion.fetch_books(config.api_key, config.books_db_id, search_title)
            if not ok_b then
                UIManager:show(InfoMessage:new{ text = _("Error: " .. tostring(books)), timeout = 5 })
                return
            end
            self:showBookMenu(config, notion, book_key, log_key, annotations, books, current_page, total_pages, search_title)
        end)
    end
end

function NotionSync:showBookMenu(config, notion, b_key, l_key, annotations, books, current_page, total_pages, search_title)
    local cp = current_page or 0
    local tp = total_pages or 0

    local items = {{ text = "➕ Create New: " .. string.sub(search_title, 1, 30), callback = function()
        local ok, id = notion.create_book(config.api_key, config.books_db_id, search_title)
        if ok then 
            G_reader_settings:saveSetting(b_key, id) 
            self:showLogMenu(config, notion, id, l_key, annotations, cp, tp) 
        else
            UIManager:show(InfoMessage:new{ text = _("Error: " .. tostring(id)), timeout = 5 })
        end
    end }}
    
    for _, b in ipairs(books or {}) do
        table.insert(items, { text = "🔗 Link to: " .. b.title, callback = function()
            G_reader_settings:saveSetting(b_key, b.id) 
            self:showLogMenu(config, notion, b.id, l_key, annotations, cp, tp)
        end })
    end
    
    UIManager:show(Menu:new{ title = "Match Book in Notion", item_table = items })
end

function NotionSync:showLogMenu(config, notion, book_id, l_key, annotations, current_page, total_pages)
    UIManager:show(InfoMessage:new{ text = _("Step 2: Select Session"), timeout = 1 })
    
    local cp = current_page or 0
    local tp = total_pages or 0

    UIManager:scheduleIn(0.5, function()
        local ok, logs = notion.fetch_reading_logs(config.api_key, config.reading_list_db_id, book_id)
        if not ok then
            UIManager:show(InfoMessage:new{ text = _("Error: " .. tostring(logs)), timeout = 5 })
            return
        end
        
        -- Use clean title for log session name
        local props = self.ui.document:getProps()
        local log_title = (props.title or "Reading") .. " Session"

        local items = {{ text = "➕ Start New Session", callback = function()
            local ok_c, id = notion.create_reading_log(config.api_key, config.reading_list_db_id, book_id, log_title)
            if ok_c then 
                G_reader_settings:saveSetting(l_key, id) 
                self:executeFinalSync(config, notion, book_id, id, annotations, cp, tp) 
            else
                UIManager:show(InfoMessage:new{ text = _("Error: " .. tostring(id)), timeout = 5 })
            end
        end }}
        if type(logs) == "table" then
            for _, l in ipairs(logs) do
                table.insert(items, { text = "🔗 Link to: " .. l.title, callback = function()
                    G_reader_settings:saveSetting(l_key, l.id) 
                    self:executeFinalSync(config, notion, book_id, l.id, annotations, cp, tp)
                end })
            end
        end
        UIManager:show(Menu:new{ title = "Select Reading Session", item_table = items })
    end)
end

function NotionSync:executeFinalSync(config, notion, b_id, l_id, annotations, current_page, total_pages)
    local cp = current_page or 0
    local tp = total_pages or 0
    local diag = string.format("Syncing: Page %d of %d", cp, tp)
    UIManager:show(InfoMessage:new{ text = diag, timeout = 2 })
    UIManager:scheduleIn(0.5, function()
        notion.update_progress(config.api_key, l_id, cp, tp)
        local _, result = notion.sync(annotations, config.api_key, config.highlights_db_id, b_id)
        UIManager:show(InfoMessage:new{ text = result, timeout = 5 })
    end)
end

function NotionSync:resetMapping()
    local m5 = util.partialMD5(self.ui.document.file)
    G_reader_settings:saveSetting("not_book_" .. m5, nil)
    G_reader_settings:saveSetting("not_log_" .. m5, nil)
    UIManager:show(InfoMessage:new{ text = _("Link reset."), timeout = 3 })
end

return NotionSync