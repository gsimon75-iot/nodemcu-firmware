------------------------------------------------------------------------------
-- HTTP server module
------------------------------------------------------------------------------

-- NOTE:
-- An http_connection is an object
-- Its constructor's a plain function which return such an object (or nil in case of error)
-- The objects contain only public data and functions
-- The private data and functions live in the closure context of the object (i.e. they are locals of the constructor)
-- The user is free to store whatever data in the objects and add whatever methods he needs

local sjson = require("sjson")

local http_response_codes = {}
http_response_codes[100] = "Continue"
http_response_codes[200] = "OK"
http_response_codes[201] = "Created"
http_response_codes[202] = "Accepted"
http_response_codes[204] = "No Content"
http_response_codes[205] = "Reset Content"
http_response_codes[206] = "Partial Content"
http_response_codes[301] = "Moved Permanently"
http_response_codes[302] = "Found"
http_response_codes[303] = "See Other"
http_response_codes[304] = "Not Modified"
http_response_codes[400] = "Bad Request"
http_response_codes[401] = "Unauthorized"
http_response_codes[403] = "Forbidden"
http_response_codes[404] = "Not Found"
http_response_codes[405] = "Method Not Allowed"
http_response_codes[406] = "Not Acceptable"
http_response_codes[408] = "Request Timeout"
http_response_codes[409] = "Conflict"
http_response_codes[410] = "Gone"
http_response_codes[411] = "Length Required"
http_response_codes[413] = "Payload Too Large"
http_response_codes[414] = "URI Too Long"
http_response_codes[415] = "Unsupported Media Type"
http_response_codes[500] = "Internal Server Error"
http_response_codes[501] = "Not Implemented"
http_response_codes[503] = "Service Unavailable"


-- Create a new http_connection object
-- on_event(http_connection, event, arg)
--   event == "-connected":     arg = nil
--   event == "-request":       arg = { method=..., path=..., proto=..., ver=... }
--   event == "-header":        arg = { name=..., value=... }
--   event == "-end-of-header"  arg = nil
--   event == "-body":          arg = data chunk
--   event == "-end-of-body":   arg = nil
--   event == "-disconnected":  arg = nil
--   event == "-error":         arg = { reason=..., data=... }
local function new_http_connection(arg_conn, on_event)
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
        -- sckt:on(whatever) callbacks *must* be reset manually, otherwise they leak the memory
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
        self.expect_100_continue = nil
        send(false)
    end

    self.start_response = function(code, message)
        local msg = message or http_response_codes[code] or "Unknown"
        self.expect_100_continue = nil
        send("HTTP/1.1 " .. code .. " " .. msg .. "\r\n")
    end

    self.send_header = function(name, value)
        send(name .. ": " .. value .. "\r\n")
    end

    self.end_header = function()
        send("\r\n")
    end

    self.reset = function()
        if self.conn_close then
            self.close()
        else
            phase = 0
            line = ""
        end
    end

    self.send_json = function(code, data)
        self.start_response(code)
        if data then
            local response = sjson.encode(data)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", response:len())
            self.end_header()
            self.send(response)
        else
            self.send_header("Content-Length", 0)
            self.end_header()
        end
        self.reset()
    end


    local function on_raw_receive(conn, payload)
        local start_pos = 1 -- next position to parse
        while true do
            if phase == 0 or phase == 1 then
                -- Parsing line-oriented parts -> collect a line or break the loop and wait for more data
                local newline_pos = payload:find("\n", start_pos, true)
                if newline_pos == nil then
                    -- Partial line -> keep collecting
                    line = line .. payload
                    break -- This chunk is processed, wait for the next one
                end
                -- Find the EOL, skipping an optional CR before the LF
                local line_end_pos = payload:byte(newline_pos - 1) == 0x0d and newline_pos - 2 or newline_pos - 1

                -- Collect this line ...
                line = line .. payload:sub(start_pos, line_end_pos)
                --- ... and skip to the next one
                start_pos = newline_pos + 1
            end
            -- Here:
            -- * If we are reading line-oriented parts (phase==0 or ==1), then we have a @line
            -- * If we are reading length-oriented part (phase==2), then we have a chunk

            if phase == 0 then
                -- Processing the request line
                local method, path, proto, ver = line:match("([A-Z]+)%s*([^%s]+)%s*([^/]+)/(.*)")
                if method ~= nil then
                    on_event(self, "-request", {method=method, path=path, proto=proto, ver=ver})
                    self.expect_100_continue = nil
                    phase = 1 -- the upcoming lines are headers
                else
                    on_event(self, "-error", {reason="BAD-REQ-LINE", data=line})
                end
                line = ""
            elseif phase == 1 then
                -- Processing header lines
                if line ~= "" then
                    -- Got a header line
                    local header_name, header_value = line:match("([^:]*):%s*(.*)")
                    if header_name ~= nil then
                        header_name = header_name:lower()
                        if header_name == "content-length" then
                            self.content_length = tonumber(header_value)
                            self.content_remaining = self.content_length
                        elseif header_name == "expect" and header_value == "100-continue" then
                            self.expect_100_continue = true
                            -- NOTE: automatically cleared by start_response and close
                        elseif header_name == "connection" and header_value == "close" then
                            self.conn_close = true
                        end
                        on_event(self, "-header", {name=header_name, value=header_value})
                    else
                        on_event(self, "-error", {reason="BAD-HDR-LINE", data=line})
                    end
                else
                    -- End of header
                    on_event(self, "-end-of-header", nil)
                    if self.content_remaining == 0 then
                        on_event(self, "-end-of-body")
                        phase = 0 -- The next request will follow
                    else
                        phase = 2 -- The body will follow
                        if self.expect_100_continue then
                            send("HTTP/1.1 100 Continue\r\n")
                        end
                    end
                end
                line = ""
            elseif phase == 2 then
                -- We're processing a body chunk
                local chunk_len = payload:len() - start_pos + 1

                if chunk_len == 0 then
                    -- Do not send an event for empty data
                    break -- processed all payload
                elseif chunk_len <= self.content_remaining then
                    -- All the payload belongs to the body
                    on_event(self, "-body", payload:sub(start_pos))
                    self.content_remaining = self.content_remaining - chunk_len
                    if self.content_remaining == 0 then
                        on_event(self, "-end-of-body")
                        phase = 0 -- will continue with the next request
                    end
                    break -- processed all payload
                else
                    -- the payload is longer than the body
                    on_event(self, "-body", payload:sub(start_pos, self.content_remaining))
                    start_pos = start_pos + self.content_remaining
                    self.content_remaining = 0
                    on_event(self, "-end-of-body")
                    phase = 0 -- continues with the next request
                end
            end
        end -- while true
    end

    local function on_connection_closed()
        on_event(self, "-disconnected") 
        clear_callbacks(arg_conn)
    end

    -- Provide an early way to refuse a connection on the IP:Port information
    on_event(self, "-connected")

    -- Register callbacks and wait for data
    arg_conn:on("receive", on_raw_receive)
    arg_conn:on("sent", on_sent)
    arg_conn:on("disconnection", on_connection_closed)
    self.reset()

    return self
end


return {
    new = new_http_connection,
}
-- vim: set sw=4 ts=4 et:
