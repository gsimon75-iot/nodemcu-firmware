
local function url_decode(s)
    -- Decode the URL-encoded characters in the path
    -- NOTE: Those byte sequences may represent utf8 chars, but as of 5.1, lua has
    -- no support for that anyway, so we treat them byte by byte
    local percent_pos = s:find("%", start, true)
    if not percent_pos then
        return s
    end

    local chunks = {}
    local start = 1
    while percent_pos do
        if percent_pos > start then
            chunks[1 + #chunks] = s:sub(start, percent_pos - 1)
        end
        local charcode = tonumber(s:sub(1 + percent_pos, 2 + percent_pos), 16)
        if charcode == nil then
            -- Invalid percent-escape -> skip percent sign (better idea?)
            start = percent_pos + 1
        else
            chunks[1 + #chunks] = string.char(charcode)
            start = percent_pos + 3
        end
        percent_pos = s:find("%", start, true)
    end
    chunks[1 + #chunks] = s:sub(start)
    return table.concat(chunks)
end

local function new_rest_router(routes)
    if routes == nil then
        return nil
    end

    local self = {
    }

    self.request = function (http_connection, method, path)
        -- Split path at slashes
        local start = path:sub(1, 1) == "/" and 2 or 1
        local path_parts = {}
        local path_len = path:len()
        while start <= path_len do
            local end_pos = path:find("/", start, true)
            if end_pos then
                path_parts[1 + #path_parts] = path:sub(start, end_pos - 1)
                start = end_pos + 1
            else
                path_parts[1 + #path_parts] = path:sub(start)
                break
            end
        end

        -- Separate the options from the last path part at the (1st) question mark
        local options = {}
        if #path_parts > 0 then
            local question_pos = path_parts[#path_parts]:find("?", 1, true)
            if question_pos ~= nil then
                -- Split option_string to options at and-signs
                start = question_pos + 1
                path_len = path_parts[#path_parts]:len()
                while start <= path_len do
                    local end_pos = path:find("&", start, true)
                    local option_string
                    if end_pos then
                        option_string = path:sub(start, end_pos - 1)
                        start = end_pos + 1
                    else
                        option_string = path:sub(start)
                        start = path_len + 1
                    end
                    -- Split the option to name and value at the (1st) equal sign
                    local equal_pos = option_string:find("=", 1, true)
                    if equal_pos then
                        options[option_string:sub(1, equal_pos - 1)] = option_string:sub(equal_pos + 1)
                    else
                        options[option_string] = ""
                    end
                end
                path_parts[#path_parts] = path_parts[#path_parts]:sub(1, question_pos - 1)
            end
        end

        -- Find the corresponding route
        http_connection.route = nil
        start = 1
        route_node = routes
        while true do
            local r = route_node[path_parts[start]]
            local rtype = type(r)
            if rtype == "table" then
                route_node = r
                start = start + 1
            elseif rtype == "function" then
                http_connection.route = r
                break
            else
                break -- illegal value type or nil
            end
        end
        if not http_connection.route then
            return false
        end

        -- We have a handler -> pass on the path parts
        http_connection:route("-request", { method = method, path = path_parts, options = options })
        return true
    end

    return self
end -- new_rest_router

return {
    new = new_rest_router,
}

-- vim: set sw=4 ts=4 et:
