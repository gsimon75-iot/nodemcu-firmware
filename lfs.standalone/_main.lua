httpserver = require("httpserver")

function on_http_connect(self, is_connected)
    if is_connected then
        local peer_port, peer_ip = self.conn:getpeer()
        print("Incoming connection; ip='" .. peer_ip .. "', port='" .. peer_port .. "'")
        -- we can store whatever we want in @self
        self.peer_ip = peer_ip
        self.peer_port = peer_port
    else
        print("Connection closed;")
    end
    return true
end


function on_http_request(self, method, path, proto, ver)
    print("Request; method='" .. method .. "', path='" .. path .. "', proto='" .. proto .. "', ver='" .. ver .. "'")
    -- we can store whatever we want in @self
    self.method = method
    self.path = path
    self.content_length = 0
end


function on_http_receive(self, chunk, header_name, header_value)
    if chunk ~= nil then
        local chunk_len = chunk:len()
        print("Request body; length='" .. chunk_len .. "', start='" .. chunk:sub(1, 16) .. "'")
        -- self.send(chunk:lower())
        self.send(chunk)
        self.content_received = self.content_received + chunk_len
        if self.content_received >= self.content_length then
            print("Request received;")
            self.close()
        end
    elseif header_name ~= nil then
        print("Request header; name='" .. header_name .. "', value='" .. header_value .. "'")
        if header_name == "content-length" then
            self.content_length = tonumber(header_value)
        end
    else
        print("Request header done;")
        self.start_response(200, "OK")
        self.send_header("X-Your-IP", self.peer_ip)
        self.send_header("X-Your-Port", self.peer_port)
        self.send_header("X-Req-Method", self.method)
        self.send_header("X-Req-Path", self.path)
        self.send_header("Content-Length", self.content_length)
        self.send_header("Content-Type", "text/plain")
        self.start_body()
        if self.content_length == 0 then
            self.close()
        else
            self.content_received = 0
        end
    end
end


function on_wifi_got_ip(T)
    print("Connected to wifi; ip='" .. T.IP .. "'")
    print("Starting server; port='80'")
    srv = httpserver.new(80, on_http_connect, on_http_request, on_http_receive)
end


print("Connecting to wifi;")
wifi.setmode(wifi.STATION)
wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, on_wifi_got_ip)
wifi.sta.config { ssid="agifules2", pwd="Pacikuki-192" }

-- vim: set sw=4 ts=4 et:
