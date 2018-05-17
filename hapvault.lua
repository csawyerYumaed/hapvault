-- Copyright 2018 Craig Sawyer
-- License MIT/Apache 2 at your preference.
-- see LICENSE
-- lots of thanks to https://github.com/TimWolla/haproxy-auth-request

local json = require("JSON")
local http = require("socket.http")
local cookie_parser = require("cookie")

function create_sock()
	local sock = core.tcp()
	sock.receive = sock.receive
	sock.settimeout = sock.timeout
	sock.old_connect = sock.connect
	sock.connect = function(addr, port)
		-- local nport = tonumber(port)
		txn.Warning("connect:" .. addr .. port)
		sock.old_connect(addr, port)
	end
	return sock
end

function create_sock_ssl()
	local sock = core.tcp()
	sock.receive = sock.receive
	sock.settimeout = sock.timeout
	sock.connect = sock.connect_ssl
	return sock
end

function split_token(val)
	local email = nil
	local vault_token = nil
	for k, v in string.gmatch(val, "(%w+):(%w+)") do
		email = k
		vault_token = v	
	end
	return email, vault_token
end

-- creates a sink that stores into a table
function sink_table(t)
    t = t or {}
    local f = function(chunk, err)
        if chunk then table.insert(t, chunk) end
        return 1
    end
    return f, t
end

core.register_action(
	"hapvault",
	{"http-req"},
	function(txn, backend, token, policy)
		txn:set_var("txn.auth_response_successful", false)
		txn:set_var("txn.auth_redirect", true)
		txn:set_var("txn.auth_response_code", 0)
		txn:set_var("txn.auth_user", nil)

		-- Transform table of request headers from haproxy's to
		-- socket.http's format.
		-- we allow the token to live either in the cookie header
		-- or in the header itself, both are OK by us.
		local headers = {}
		local cookies = {}
		local token_value = ""
		for header, values in pairs(txn.http:req_get_headers()) do
			for i, v in pairs(values) do
				-- txn:Debug("hapvault:incoming from haproxy headers:" .. header .. ": " .. v)
				if header == "cookie" then
					cookies = cookie_parser.get_cookie_table(v)
				end
				if header == token then
					token_value = v
				end
				if headers[header] == nil then
					headers[header] = v
				else
					headers[header] = headers[header] .. ", " .. v
				end
			end
		end
		for k,v in pairs(cookies) do 
			if k == token then
				token_value = v
			end
			-- txn:Debug("hapvault:cookies:" .. k .. ": " .. v) 
		end
		-- token checkout time!
		-- if we do not have it around, just punt and kick the user off to authenticate.
		-- this is the fast path.
		if token_value == nil then
			-- txn:Info("hapvault:adding Location header:" .. headers["x-redirect-url"])
			-- txn.http:req_set_header("Location", redirect_addr .. h["location"])
			txn:set_var("txn.auth_redirect", true)
			txn:set_var("txn.auth_redirect_location", headers["x-redirect-url"] .. "?service=" .. headers["x-requesting-url"])
			return
		end
		vault_token = token_value

		-- txn:Debug("hapvault:splitting:" .. vault_token)
		--SETTING
		--this is local ot my use-case I need the token to be a : split of username:vault token
		-- if you do not need this, comment out the next 2 lines with --
		email, vault_token = split_token(vault_token)

		headers["X-Vault-Token"] = vault_token
		-- txn:Debug("set X-Vault-Token header to:" .. vault_token)
		
		-- Check whether the given backend exists.
		if core.backends[backend] == nil then
			txn:Alert("hapvault:Unknown auth-request backend '" .. backend .. "'")
			txn:set_var("txn.auth_response_code", 500)
			return
		end

		-- Check whether the given backend has servers that
		-- are not `DOWN`.
		local addr = nil
		for name, server in pairs(core.backends[backend].servers) do
			local stats = server:get_stats()
			for k,v in pairs(stats) do txn:Debug(k .. ": " .. v) end
			if stats["status"] ~= "DOWN" then
				addr = server:get_addr()
				break
			end
		end
		if addr == nil then
			txn:Warning("hapvault:No servers available for auth-request backend: '" .. backend .. "'")
			txn:set_var("txn.auth_response_code", 500)
			return
		end

		request_url = "http://" .. addr .. "/v1/auth/token/lookup-self"
		txn:Debug("backend url:" .. request_url)
		-- for k,v in pairs(headers) do txn:Debug("hapvault:sending to vault headers:" .. k .. ": " .. v) end
		
		-- Make request to backend.
		local ret={}
		local r, c, h =
			http.request {
			url = request_url,
			headers = headers,
			sink = sink_table(ret),
			target = ret,
			-- create = create_sock_ssl,
			-- create = create_sock,
			-- Disable redirects, because DNS does not work here.
			redirect = false}
		

		-- Check whether we received a valid HTTP response.
		if r == nil then
			txn:Warning("hapvault:Failure in auth-request backend '" .. backend .. "': " .. c)
			txn:set_var("txn.auth_response_code", 500)
			return
		end

		-- for key, value in pairs(h) do txn:Debug("hapvault:vault returning headers:" .. key .. ":" .. value) end
		
		-- 2xx: Allow request.
		if 200 <= c and c < 300 then
			local body = json:decode(table.concat(ret))
			-- txn:Info("body from auth backend:" .. body)
			for k,v in pairs(body['data']['policies']) do
				-- txn:Debug("hapvoult:policy:" .. v)
				if v == policy then
					txn:set_var("txn.auth_response_successful", true)
					txn:set_var("txn.auth_redirect", false)
					txn:set_var("txn.auth_response_code", c)
					txn:set_var("txn.auth_user", email)
				end
			end
		else
			-- 400 vault permission denied, so either a bad token, or no token sent for whatever reason.
			-- txn:Debug("hapvault:status code in auth-request backend '" .. backend .. "': " .. c)
			-- txn:Debug("hapvault:adding Location header:" .. headers["x-redirect-url"])
			txn:set_var("txn.auth_redirect_location", headers["x-redirect-url"] .. "?service=" .. headers["x-requesting-url"])
			txn:set_var("txn.auth_response_code", c)
		end
	end,
	3
)
