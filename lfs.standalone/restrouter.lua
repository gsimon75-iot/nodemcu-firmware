
local function new_rest_router(routes)
    if routes == nil then
        return nil
    end

    local self = {
    }

    self.request = function (http_connection, method, path)
        -- Split path at slashes
        local path_parts = {}
        local start = path:sub(1, 1) == "/" and 2 or 1
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
        http_connection:route("-request", { method = method, path = path_parts})
        return true
    end

    return self
end -- new_rest_router

return {
    new = new_rest_server,
}

-- vim: set sw=4 ts=4 et:
