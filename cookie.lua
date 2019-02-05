-- This module is licensed under the BSD license.
-- Copyright (C) 2013, by Jiale Zhi vipcalio@gmail.com, CloudFlare Inc.
-- Copyright (C) 2013, by Yichun Zhang agentzh@gmail.com, CloudFlare Inc.
-- Copyright (C) 2018, by Craig Sawyer csawyer@yumaed.org, YUHSD #70
--Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
-- Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
-- Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

-- Code originally from: 

local type = type
local byte = string.byte
local sub = string.sub
local format = string.format

local EQUAL = byte("=")
local SEMICOLON = byte(";")
local SPACE = byte(" ")
local HTAB = byte("\t")

local cookiemodule = {}
function cookiemodule.get_cookie_table(text_cookie)
	if type(text_cookie) ~= "string" then
		return {}
	end
	local EXPECT_KEY = 1
	local EXPECT_VALUE = 2
	local EXPECT_SP = 3

	local n = 0
	local len = #text_cookie

	for i = 1, len do
		if byte(text_cookie, i) == SEMICOLON then
			n = n + 1
		end
	end
	
	local cookie_table = {}
	
	local state = EXPECT_SP
	local i = 1
	local j = 1
	local key, value

	while j <= len do
		if state == EXPECT_KEY then
			if byte(text_cookie, j) == EQUAL then
				key = sub(text_cookie, i, j - 1)
				state = EXPECT_VALUE
				i = j + 1
			end
		elseif state == EXPECT_VALUE then
			if byte(text_cookie, j) == SEMICOLON or byte(text_cookie, j) == SPACE or byte(text_cookie, j) == HTAB then
				value = sub(text_cookie, i, j - 1)
				cookie_table[key] = value

				key, value = nil, nil
				state = EXPECT_SP
				i = j + 1
			end
		elseif state == EXPECT_SP then
			if byte(text_cookie, j) ~= SPACE and byte(text_cookie, j) ~= HTAB then
				state = EXPECT_KEY
				i = j
				j = j - 1
			end
		end
		j = j + 1
	end

	if key ~= nil and value == nil then
		cookie_table[key] = sub(text_cookie, i)
	end

	return cookie_table
end
return cookiemodule
