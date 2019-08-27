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
function new_http_connection(arg_conn, cbk_on_connect, cbk_on_request, cbk_on_receive)
    local self = {
        conn = arg_conn, -- the connection
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

    local function on_receive_body(conn, payload)
        -- We're processing a body chunk
        cbk_on_receive(self, payload, nil, nil)
    end

    local function on_receive_request(conn, payload)
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
                    cbk_on_request(self, method, path, proto, ver)
                    phase = 1 -- the upcoming lines are headers
                else
                    -- FIXME: Invalid request line, now what?
                end
            else
                -- Processing header lines
                if line == "" then
                    -- End of header lines, body will follow
                    conn:on("receive", on_receive_body)
                    -- Signal the end of header condition
                    cbk_on_receive(self, nil, nil, nil)
                    -- Pass the remainder (if any) as a body chunk
                    if newline_pos < payload:len() then
                        cbk_on_receive(self, payload:sub(newline_pos + 1), nil, nil)
                    end
                    break -- This chunk is done, wait for the next one
                else
                    -- Got a header line
                    local header_name, header_value = line:match("([^:]*):%s*(.*)")
                    if header_name ~= nil then
                        cbk_on_receive(self, nil, header_name:lower(), header_value)
                    else
                        -- FIXME: Invalid header line, now what?
                    end
                end
            end -- phase == { 0, 1 }

            line = ""
        end -- while true
    end

    local function on_connection_closed()
        if cbk_on_connect ~= nil then
            cbk_on_connect(self, false) 
        end
        clear_callbacks(arg_conn)
    end

    self.request_processed = function()
        phase = 0
        line = ""
        arg_conn:on("receive", on_receive_request)
    end

    -- Provide an early way to refuse a connection on the IP:Port information
    if cbk_on_connect ~= nil then
        if not cbk_on_connect(self, true) then
            arg_conn:close()
            return nil
        end
    end

    -- Register callbacks and wait for data
    arg_conn:on("sent", on_sent)
    arg_conn:on("disconnection", on_connection_closed)
    self.request_processed()

    return self
end


function new_http_server(port, cbk_on_connect, cbk_on_request, cbk_on_receive)
    -- cbk_on_connect(http_connection, is_connected), ret: bool -> true=accept, false=refuse
    -- cbk_on_request(http_connection, method, path, proto, ver)
    -- cbk_on_receive(http_connection, chunk, header_name, header_value)

    -- Check mandatory callbacks
    if cbk_on_request == nil or cbk_on_receive == nil then
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
        new_http_connection(conn, cbk_on_connect, cbk_on_request, cbk_on_receive)
    end)

    return self
end -- new_http_server


http_server_factory = {
    -- Create a new http_server that is listening on a port
    new = new_http_server,
}

return http_server_factory
-- vim: set sw=4 ts=4 et:
