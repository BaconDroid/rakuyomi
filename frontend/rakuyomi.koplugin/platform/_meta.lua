---@meta

---@class Platform
local Platform = {}

---@return Server
function Platform:startServer()
end

--- @class ServerRequest
--- @field path string The request path.
--- @field method string? The request method. Defaults to "GET".
--- @field body string? The request body to be sent.
--- @field headers table<string, string>? The headers to be sent with the request.
--- @field timeout_seconds number? How many seconds until the request times out. Defaults to 60 seconds.

--- @class Server
local Server = {}

--- Performs an HTTP request to the server.
---
--- @param request ServerRequest The request definition.
--- @return { type: 'ERROR', message: string }|{ type: 'RESPONSE', status: number, body: string }
function Server:request(request)
end

--- Gets the last log lines written by the server.
--- @return string[]
function Server:getLogBuffer()
end

--- Whether the server process is still running. Optional: servers that cannot
--- observe their process (e.g. Android) do not implement it.
--- @return boolean
function Server:is_alive()
end

--- Stops the server.
--- @return boolean|nil success False when the child could not be reaped; nil when
function Server:stop()
end
