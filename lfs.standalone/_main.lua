httpserver = require("httpserver")
restrouter = require("restrouter")

schemes = {
    wave =              { 1, 2, 3, 4 },
    fullstep =          { 1, 2, 3, 4 },
    halfstep =          { 1, 2, 3, 4 },
    halfstep_w_ena =    { 1, 2, 3, 4 },
}

speed = 2400
scheme = schemes.fullstep

function rest_speed(self, event, arg)
    if event == "-request" then
        print("Speed; method='" .. arg.method .. "', #path='" .. #arg.path .. "'")
        for i, v in ipairs(arg.path) do
            print("Speed path; idx='" .. i .. "', value='" .. v .. "'")
        end

        if arg.method == "GET" and #arg.path == 1 then
            print("Speed queried;")
            self.send_json(200, { speed = speed })
            return
        end

        if arg.method == "POST" and #arg.path == 2 then
            print("Setting speed; value='" .. arg.path[2] .. "'")
            local new_speed = tonumber(arg.path[2])
            if new_speed ~= nil then
                speed = new_speed
                print("Speed set; speed='" .. speed .. "'")
                self.send_json(202)
                return
            end
        end
        self.send_json(400)
    end
    -- We don't (yet) need to handle headers nor the request body
end

function rest_scheme(self, event, arg)
end

function rest_step_to(self, event, arg)
end

function rest_step_by(self, event, arg)
end

router = restrouter.new(
{ 
    speed = rest_speed,
    scheme = rest_scheme,
    step = 
    {
        to = rest_step_to,
        by = rest_step_by,
    },
})

function on_http_event(self, event, arg)
    if self.route then
        self:route(event, arg)
    elseif event == "-request" then
        if not router.request(self, arg.method, arg.path) then
            -- Now we don't have any other type of content
            self.send_json(404)
        end
    end
end


function on_wifi_got_ip(T)
    local port = 80
    print("Connected to wifi, starting server; ip='" .. T.IP .. "', port='" .. port .. "'")
    local srv = net.createServer(net.TCP, 15)
    srv:listen(port, function(conn)
        httpserver.new(conn, on_http_event)
    end)
end


print("Connecting to wifi;")
wifi.setmode(wifi.STATION)
wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, on_wifi_got_ip)
wifi.sta.config { ssid="qwerqwer", pwd="asdfasdf" }

-- vim: set sw=4 ts=4 et:
