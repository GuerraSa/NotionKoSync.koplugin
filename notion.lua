local M = {}

local function request(method, url, payload, api_key)
    local json = require("json")
    local https = require("ssl.https")
    local ltn12 = require("ltn12")
    local response_body = {}
    local req_body = payload and json.encode(payload) or ""
    local headers = {
        ["Authorization"] = "Bearer " .. api_key,
        ["Notion-Version"] = "2022-06-28",
        ["Content-Type"] = "application/json",
        ["Content-Length"] = tostring(#req_body)
    }
    local res, code = https.request({
        url = url, method = method, headers = headers,
        source = ltn12.source.string(req_body),
        sink = ltn12.sink.table(response_body)
    })
    if not res then return "Network Error", 500 end
    return table.concat(response_body), tonumber(code) or 500
end

-- NEW: fetch_books now takes a 'search_title' parameter
function M.fetch_books(api_key, books_db_id, search_title)
    local json = require("json")
    local payload = {
        filter = {
            property = "Name", -- Ensure your Title property in the Books DB is named "Name"
            rich_text = {
                contains = search_title
            }
        }
    }
    
    local res, code = request("POST", "https://api.notion.com/v1/databases/" .. books_db_id .. "/query", payload, api_key)
    if code ~= 200 then return false, "Fetch failed (Code " .. code .. ")" end
    
    local data = json.decode(res)
    local books = {}
    for _, page in ipairs(data.results or {}) do
        local title = "Untitled"
        for k, v in pairs(page.properties) do
            if v.type == "title" and v.title[1] then title = v.title[1].text.content end
        end
        table.insert(books, { id = page.id, title = title })
    end
    return true, books
end

function M.create_book(api_key, books_db_id, title)
    local json = require("json")
    local payload = { parent = { database_id = books_db_id }, properties = { ["Name"] = { title = {{ text = { content = title } }} } } }
    local res, code = request("POST", "https://api.notion.com/v1/pages", payload, api_key)
    if code == 200 then return true, json.decode(res).id end
    return false, "Create failed"
end

function M.fetch_reading_logs(api_key, reading_list_db_id, book_id)
    local json = require("json")
    local payload = {
        filter = { property = "Title", relation = { contains = book_id } },
        sorts = { { timestamp = "last_edited_time", direction = "descending" } }
    }
    local res, code = request("POST", "https://api.notion.com/v1/databases/" .. reading_list_db_id .. "/query", payload, api_key)
    if code ~= 200 then return false, "Log fetch failed" end
    local data = json.decode(res)
    local logs = {}
    for _, page in ipairs(data.results or {}) do
        local title = "Log Entry"
        for k, v in pairs(page.properties) do
            if v.type == "title" and v.title[1] then title = v.title[1].text.content end
        end
        table.insert(logs, { id = page.id, title = title })
    end
    return true, logs
end

function M.create_reading_log(api_key, reading_list_db_id, book_id, log_title)
    local json = require("json")
    local payload = {
        parent = { database_id = reading_list_db_id },
        properties = {
            ["Name"] = { title = {{ text = { content = log_title } }} },
            ["Title"] = { relation = {{ id = book_id }} }
        }
    }
    local res, code = request("POST", "https://api.notion.com/v1/pages", payload, api_key)
    if code == 200 then return true, json.decode(res).id end
    return false, "Log create failed"
end

function M.update_progress(api_key, log_id, current_page, total_pages)
    local utc_now = os.time(os.date("!*t"))
    local vancouver_time = utc_now - (8 * 3600) 
    local time_str = os.date("%Y-%m-%dT%H:%M:%S", vancouver_time)
    
    local payload = { 
        properties = { 
            ["Progress"] = { number = current_page },
            ["Total Pages"] = { number = total_pages },
            ["Last Synced"] = { date = { start = time_str } }
        } 
    }
    request("PATCH", "https://api.notion.com/v1/pages/" .. log_id, payload, api_key)
end

local function fetch_existing_highlights(api_key, highlights_db_id, relation_id)
    local json = require("json")
    local existing = {}
    local res, code = request("POST", "https://api.notion.com/v1/databases/" .. highlights_db_id .. "/query", { filter = { property = "Book", relation = { contains = relation_id } } }, api_key)
    if code == 200 then
        local data = json.decode(res)
        for _, page in ipairs(data.results or {}) do
            local p = page.properties["Annotation"]
            if p and p.title[1] then existing[p.title[1].text.content] = true end
        end
    end
    return existing
end

function M.sync(annotations, api_key, highlights_db_id, relation_id)
    local synced, skipped = 0, 0
    local existing = fetch_existing_highlights(api_key, highlights_db_id, relation_id)
    for _, ann in ipairs(annotations) do
        if ann.text and ann.text ~= "" then
            local txt = string.sub(ann.text, 1, 1999)
            if not existing[txt] then
                local payload = {
                    parent = { database_id = highlights_db_id },
                    properties = {
                        ["Annotation"] = { title = {{ text = { content = txt } }} },
                        ["Book"] = { relation = {{ id = relation_id }} }
                    }
                }
                local raw_p = ann.page or ann.pagenum or (ann.pos0 and ann.pos0.page)
                if raw_p then 
                    local p_num = tonumber(tostring(raw_p):match("%d+"))
                    if p_num then payload.properties["Page"] = { number = p_num } end
                end
                local _, code = request("POST", "https://api.notion.com/v1/pages", payload, api_key)
                if code == 200 then synced = synced + 1 end
            else skipped = skipped + 1 end
        end
    end
    return true, "Synced " .. synced .. ". Skipped " .. skipped
end

return M