# KOReader Notion Sync

A KOReader plugin that synchronizes your book highlights and reading progress directly to Notion. 

Unlike basic sync tools, this plugin supports a **relational database structure**, separating your permanent book library from your individual reading sessions. This allows you to track re-reads, exact page progress, and timestamps without cluttering your core library data.

## Features
* **Smart Book Matching:** Automatically searches your Notion library using the book's metadata to prevent duplicate entries.
* **Relational Tracking:** Links highlights to a core `Books` database while logging page progress to a specific `Reading List` session.
* **Granular Progress Syncing:** Pushes your exact current page and total page count to Notion.
* **Time-Stamped Logs:** Records exactly when you last synced (with timezone support).
* **Highlight Deduplication:** Checks existing Notion entries so you never upload the same highlight twice.

## Notion Database Setup

To use this plugin, you need two linked databases in Notion.

### 1. Books Database
This acts as your permanent library.
* **Name** (`Title` property): The title of the book.

### 2. Reading List Database
This tracks your specific reading sessions (allowing for re-reads).
* **Name** (`Title` property): The name of the session (e.g., "Think and Grow Rich Session").
* **Title** (`Relation` property): Linked to your **Books Database**.
* **Progress** (`Number` property): Tracks your current page.
* **Total Pages** (`Number` property): Tracks the length of the book.
* **Last Synced** (`Date` property): Tracks when you last read. *(Tip: Set this property to "Include Time" in Notion).*

## Installation

1. Download or clone this repository.
2. Connect your e-reader via USB.
3. Copy the `NotionSync.koplugin` folder into your KOReader plugins directory:
   * **Kobo:** `.adds/koreader/plugins/`
4. Create a `config.lua` file inside the `NotionSync.koplugin` folder with your Notion API details (see below).
5. Restart KOReader.

## Configuration (`config.lua`)

You must create a `config.lua` file inside the plugin folder. Do not commit this file to GitHub if your repository is public!

```lua
local M = {}

M.api_key = "secret_YOUR_NOTION_INTEGRATION_KEY"
M.highlights_db_id = "YOUR_HIGHLIGHTS_DB_ID" -- (Optional: If you use a 3rd DB for highlights)
M.books_db_id = "YOUR_BOOKS_DB_ID"
M.reading_list_db_id = "YOUR_READING_LIST_DB_ID"

return M
