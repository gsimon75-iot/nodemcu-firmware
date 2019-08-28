------------------------------------------------------------------------------
-- HTTP server module
------------------------------------------------------------------------------

-- NOTE:
-- http_connection and http_server are objects
-- Their constructors are plain functions which return such objects (or nil in case of error)
-- The objects contain only public data and functions
-- The private data and functions live in the closure context of the object (i.e. they are locals of the constructor)
-- The user is free to store whatever data in the objects and add whatever methods he needs
-- sckt:on(whatever) callbacks *must* be reset manually, otherwise they leak the memory

-- Create a new http_connection object
function new_http_connection(arg_conn, on_event)
    local self = {
        conn = arg_conn, -- the connection
        content_length = 0,
        content_remaining = 0,
    }

    local phase = 0 -- processing phase, 0: request line, 1: headers, 2: body
    local line = "" -- line fragment buffer, used only while reading headers
    local output_queue = {} -- pending data to be sent
    local idle = true

    local function clear_callbacks(sckt)
        sckt:on("sent", nil)
        sckt:on("receive", nil)
        sckt:on("disconnection", nil)
    end

    -- Callback: proceed to the next output chunk
    local function on_sent(sckt)
        if #output_queue == 0 then
            idle = true
        else
            local data = table.remove(output_queue, 1)
            if type(data) == "string" then
                sckt:send(data)
            else
                clear_callbacks(sckt)
                sckt:close()
            end
        end
    end

    -- Send some data
    local function send(data)
        output_queue[1 + #output_queue] = data
        if idle then
            -- no sending is in progress -> call on_sent manually to begin
            idle = false
            on_sent(arg_conn)
        end
    end

    -- Public wrappers around send(...)
    self.send = send

    self.close = function()
        send(false)
    end

    self.start_response = function(code, message)
        send("HTTP/1.1 " .. code .. " " .. message .. "\r\n")
    end

    self.send_header = function(name, value)
        send(name .. ": " .. value .. "\r\n")
    end

    self.start_body = function()
        send("\r\n")
    end

    local function on_event_body(conn, payload)
        -- We're processing a body chunk
        local payload_len = payload:len()
        if payload_len == 0 then
            -- do not send an event for empty data
        elseif payload_len <= self.content_remaining then
            on_event(self, "-body", payload)
            self.content_remaining = self.content_remaining - payload_len
        else
            on_event(self, "-body", payload:sub(1, self.content_remaining))
            -- FIXME: handle payload:sub(self.content_remaining + 1)
            self.content_remaining = 0
        end

        if self.content_remaining <= 0 then
            on_event(self, "-end-of-body")
        end
    end

    local function on_event_request(conn, payload)
        -- We're processing either the request line or a header
        -- Both are line-oriented, so we need to read until LF
        local line_start_pos = 1
        while true do
            local newline_pos = payload:find("\n", line_start_pos, true)
            if newline_pos == nil then
                -- Partial line -> keep collecting
                line = line .. payload
                break -- This chunk is processed, wait for the next one
            end
            -- Find the EOL, skipping an optional CR before the LF
            local line_end_pos = payload:byte(newline_pos - 1) == 0x0d and newline_pos - 2 or newline_pos - 1

            -- Collect this line ...
            line = line .. payload:sub(line_start_pos, line_end_pos)
            --- ... and skip to the next one
            line_start_pos = newline_pos + 1

            if phase == 0 then
                -- Processing the request line
                local method, path, proto, ver = line:match("([A-Z]+)%s*([^%s]+)%s*([^/]+)/(.*)")
                if method ~= nil then
                    on_event(self, "-request", {method=method, path=path, proto=proto, ver=ver})
                    phase = 1 -- the upcoming lines are headers
                else
                    on_event(self, "-error", {reason="BAD-REQ-LINE", data=line})
                    -- skip and proceed
                end
            else
                -- Processing header lines
                if line == "" then
                    -- End of header lines, body will follow
                    conn:on("receive", on_event_body)
                    -- Signal the end of header condition
                    on_event(self, "-end-of-header", nil)
                    -- Pass the remainder (if any) as a body chunk
                    on_event_body(self, payload:sub(newline_pos + 1))
                    break -- This chunk is done, wait for the next one
                else
                    -- Got a header line
                    local header_name, header_value = line:match("([^:]*):%s*(.*)")
                    if header_name ~= nil then
                        header_name = header_name:lower()
                        if header_name == "content-length" then
                            self.content_length = tonumber(header_value)
                            self.content_remaining = self.content_length
                        end
                        on_event(self, "-header", {name=header_name, value=header_value})
                    else
                        on_event(self, "-error", {reason="BAD-HDR-LINE", data=line})
                        -- skip and proceed
                    end
                end
            end -- phase == { 0, 1 }

            line = ""
        end -- while true
    end

    local function on_connection_closed()
        on_event(self, "-disconnected") 
        clear_callbacks(arg_conn)
    end

    self.request_processed = function()
        phase = 0
        line = ""
        arg_conn:on("receive", on_event_request)
    end

    -- Provide an early way to refuse a connection on the IP:Port information
    if not on_event(self, "-connected") then
        arg_conn:close()
        return nil
    end

    -- Register callbacks and wait for data
    arg_conn:on("sent", on_sent)
    arg_conn:on("disconnection", on_connection_closed)
    self.request_processed()

    return self
end


function new_http_server(port, on_event)
    -- on_event(http_connection, event, arg)
    --   event == "-connected":     arg = nil, ret = bool -> true=accept, false=refuse
    --   event == "-request":       arg = { method=..., path=..., proto=..., ver=... }
    --   event == "-header":        arg = { name=..., value=... }
    --   event == "-end-of-header"  arg = nil
    --   event == "-body":          arg = data chunk
    --   event == "-disconnected":  arg = nil
    --   event == "-error":         arg = { reason=..., data=... }

    if on_event == nil then
        return nil
    end

    local self = {
        srv = net.createServer(net.TCP, 15),
    }

    self.close = function()
        if self.srv then
            self.srv:close()
            self.srv = nil
        end
    end

    -- Start listening
    self.srv:listen(port, function(conn)
        new_http_connection(conn, on_event)
    end)

    return self
end -- new_http_server


http_server_factory = {
    -- Create a new http_server that is listening on a port
    new = new_http_server,
}

return http_server_factory
-- vim: set sw=4 ts=4 et:
