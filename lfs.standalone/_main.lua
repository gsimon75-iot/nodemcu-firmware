httpserver = require("httpserver")
restrouter = require("restrouter")
stepper_motor = require("stepper_motor")

function toboolean(s)
    return (s == "true") and true or ((s == false) and false) or nil
end

function rest_speed(self, event, arg)
    if event == "-request" then
        if arg.method == "GET" and #arg.path == 1 then
            print("Speed queried;")
            self.send_json(200, { speed = motor.speed })
            return
        end

        if arg.method == "POST" and #arg.path == 2 then
            print("Setting speed; value='" .. arg.path[2] .. "'")
            local new_speed = tonumber(arg.path[2])
            if new_speed ~= nil then
                motor.set_speed(new_speed)
                self.send_json(202)
                return
            end
        end

        self.send_json(400)
    end
end

function rest_scheme(self, event, arg)
    if event == "-request" then
        if arg.method == "GET" and #arg.path == 1 then
            print("Scheme queried;")
            self.send_json(200, { scheme = motor.scheme_name })
            return
        end

        if arg.method == "PUT" and #arg.path == 2 then
            print("Change scheme; value='" .. arg.path[2] .. "'")
            if motor.set_scheme(arg.path[2]) then
                self.send_json(202)
                return
            end
        end

        self.send_json(400)
    end
end

function rest_position(self, event, arg)
    if event == "-request" then
        if arg.method == "GET" and #arg.path == 1 then
            print("Position queried;")
            self.send_json(200, { position = motor.position })
            return
        end

        if arg.method == "PUT" and #arg.path == 2 then
            print("Move to; value='" .. arg.path[2] .. "'")
            local new_pos = tonumber(arg.path[2])
            if new_pos ~= nil then
                motor.step_to(new_pos)
                self.send_json(202)
                return
            end
        end

        if arg.method == "PATCH" and #arg.path == 2 then
            print("Move by; value='" .. arg.path[2] .. "'")
            local new_pos = tonumber(arg.path[2])
            if new_pos ~= nil then
                motor.step_by(new_pos)
                self.send_json(202)
                return
            end
        end

        self.send_json(400)
    end
end

function rest_lock(self, event, arg)
    if event == "-request" then
        if arg.method == "GET" and #arg.path == 1 then
            print("Lock policy queried;")
            self.send_json(200, { lock = motor.keep_locked })
            return
        end

        if arg.method == "PUT" and #arg.path == 2 then
            print("Change lock policy; value='" .. arg.path[2] .. "'")
            local new_lock = toboolean(arg.path[2])
            if new_lock ~= nil then
                motor.set_lock_policy(new_lock)
                self.send_json(202)
                return
            end
        end

        if arg.method == "DELETE" and #arg.path == 1 then
            print("Releasing lock;")
            motor.release()
            self.send_json(202)
            return
        end

        self.send_json(400)
    end
end

router = restrouter.new(
{ 
    speed = rest_speed,
    scheme = rest_scheme,
    position = rest_position,
    lock = rest_lock,
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
    motor = stepper_motor.new({
        A_pos = 4, -- GPIO2
        A_neg = 7, -- GPIO13
        A_ena = 8, -- GPIO15
        B_pos = 6, -- GPIO12
        B_neg = 5, -- GPIO14
        B_ena = 0, -- GPIO16
    })
end

node.setcpufreq(node.CPU160MHZ)
print("Connecting to wifi;")
wifi.setmode(wifi.STATION)
wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, on_wifi_got_ip)
wifi.sta.config { ssid="qwerqwer", pwd="asdfasdf" }

-- vim: set sw=4 ts=4 et:
