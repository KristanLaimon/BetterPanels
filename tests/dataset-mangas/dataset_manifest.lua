--- Dataset manifest loader for Manga panel evaluation.
---
--- Parses and normalizes dataset metadata and ground-truth frames.

local JSON = require("tests.helpers.json")

local Manifest = {
    _manga_cache = nil,
}

local DEFAULT_MANGA_DIR = "tests/dataset-mangas/dataset"
local FALLBACK_MANGA_DIR = "tests/dataset-mangas/dataset-private"

--- Load and cache manga dataset.
---
--- @param dataset_dir string|nil Path to dataset directory (defaults to "tests/dataset-mangas/dataset")
--- @return table List of books with pages and annotations
function Manifest.loadManga(dataset_dir)
    if not dataset_dir then
        local f_test = io.open(DEFAULT_MANGA_DIR .. "/annotation.json", "r")
        if f_test then
            f_test:close()
            dataset_dir = DEFAULT_MANGA_DIR
        else
            dataset_dir = FALLBACK_MANGA_DIR
        end
    end

    if Manifest._manga_cache and Manifest._manga_cache[dataset_dir] then
        return Manifest._manga_cache[dataset_dir]
    end

    local annotation_path = dataset_dir .. "/annotation.json"
    local f, err = io.open(annotation_path, "r")
    if not f then
        Manifest._manga_cache = Manifest._manga_cache or {}
        Manifest._manga_cache[dataset_dir] = {}
        return {}
    end
    local raw_json = f:read("*a")
    f:close()

    local raw_books = JSON.decode(raw_json)
    if not raw_books then
        Manifest._manga_cache = Manifest._manga_cache or {}
        Manifest._manga_cache[dataset_dir] = {}
        return {}
    end

    local books = {}
    for _, raw_book in ipairs(raw_books) do
        local book = {
            book_title = raw_book.book_title,
            pages = {},
        }
        for _, raw_page in ipairs(raw_book.pages or {}) do
            local rel_img = raw_page.image_paths and raw_page.image_paths.ja
            local img_path = rel_img and (dataset_dir .. "/" .. rel_img) or nil
            local frames = {}
            for _, rf in ipairs(raw_page.frame or {}) do
                table.insert(frames, {
                    x = rf.x,
                    y = rf.y,
                    w = rf.w,
                    h = rf.h,
                })
            end

            table.insert(book.pages, {
                dataset = "manga",
                book_title = raw_book.book_title,
                page_index = raw_page.page_index,
                image_path = img_path,
                reading_order = "manga",
                frames = frames,
                text = raw_page.text or {},
            })
        end
        table.insert(books, book)
    end

    Manifest._manga_cache = Manifest._manga_cache or {}
    Manifest._manga_cache[dataset_dir] = books
    return books
end

--- Get all pages across all books as a flat list.
---
--- @param dataset_dir string|nil
--- @return table Array of page records
function Manifest.getAllPages(dataset_dir)
    local books = Manifest.loadManga(dataset_dir)
    local all_pages = {}
    for _, book in ipairs(books) do
        for _, page in ipairs(book.pages) do
            table.insert(all_pages, page)
        end
    end
    return all_pages
end

--- Find a specific page by book title and page index.
---
--- @param book_title string
--- @param page_index integer
--- @param dataset_dir string|nil
--- @return table|nil
function Manifest.getPage(book_title, page_index, dataset_dir)
    local books = Manifest.loadManga(dataset_dir)
    for _, book in ipairs(books) do
        if book.book_title == book_title then
            for _, page in ipairs(book.pages) do
                if page.page_index == page_index then
                    return page
                end
            end
        end
    end
    return nil
end

--- Curated golden set of representative manga pages across all books.
---
--- Covers varied panel layouts, gutter widths, and frame structures.
---
--- @param dataset_dir string|nil
--- @return table Array of representative page records
function Manifest.getGoldenPages(dataset_dir)
    local golden_specs = {
        { book = "tojime_no_siora", page = 2 },
        { book = "balloon_dream", page = 4 },
        { book = "tencho_isoro", page = 2 },
        { book = "boureisougi", page = 3 },
        { book = "rasetugari", page = 1 },
    }

    local pages = {}
    for _, spec in ipairs(golden_specs) do
        local page = Manifest.getPage(spec.book, spec.page, dataset_dir)
        if page then
            table.insert(pages, page)
        end
    end

    if #pages == 0 then
        local all_pages = Manifest.getAllPages(dataset_dir)
        for i = 1, math.min(5, #all_pages) do
            table.insert(pages, all_pages[i])
        end
    end
    return pages
end

return Manifest
