local bit = require('bit')
local ffi = require('ffi')
local C = ffi.C
local UIManager = require('ui/uimanager')
local util = {}

---@param operation string
---@param return_code number
function util.must(operation, return_code)
  if return_code < 0 then
    error("failed to " .. operation .. ": " .. ffi.string(C.strerror(ffi.errno())))
  end

  return return_code
end

--- Like must(), but for posix_spawn APIs that return the error code directly
--- (0 on success, positive errno on failure) instead of -1 + errno.
---@param operation string
---@param return_code number
function util.must0(operation, return_code)
  if return_code ~= 0 then
    error("failed to " .. operation .. ": " .. ffi.string(C.strerror(return_code)))
  end

  return return_code
end

local F_SETFL = 4
local O_NONBLOCK = 0x4
local POLLHUP = 0x10

---@class SubprocessOutputCapturer
---@diagnostic disable-next-line: undefined-doc-name
---@field stdout_pipe ffi.cdata*
---@diagnostic disable-next-line: undefined-doc-name
---@field stderr_pipe ffi.cdata*
---@field stdoutEof boolean Whether the stdout pipe already reported EOF.
---@field stderrEof boolean Whether the stderr pipe already reported EOF.
---@field pollTask (fun():nil)|nil The pending scheduled poll, if any.
local SubprocessOutputCapturer = {}

local function close_fd(pipe, index)
  if pipe[index] >= 0 then
    C.close(pipe[index])
    pipe[index] = -1
  end
end

---@return SubprocessOutputCapturer
function SubprocessOutputCapturer:new()
  local obj = {
    stdout_pipe = ffi.new("int[2]"),
    stderr_pipe = ffi.new("int[2]"),
    stdoutEof = false,
    stderrEof = false,
  }
  setmetatable(obj, { __index = self })

  util.must("create stdout pipe", C.pipe(obj.stdout_pipe))
  util.must("create stderr pipe", C.pipe(obj.stderr_pipe))

  -- Set reading end to non-blocking
  util.must("set stdout non-blocking", C.fcntl(obj.stdout_pipe[0], F_SETFL, O_NONBLOCK))
  util.must("set stderr non-blocking", C.fcntl(obj.stderr_pipe[0], F_SETFL, O_NONBLOCK))

  return obj
end

function SubprocessOutputCapturer:setupChildProcess()
  -- Redirect stdout to write end of pipe
  util.must("dup2 stdout", C.dup2(self.stdout_pipe[1], 1))
  util.must("dup2 stderr", C.dup2(self.stderr_pipe[1], 2))

  -- Close reading ends in child
  C.close(self.stdout_pipe[0])
  C.close(self.stderr_pipe[0])
end

function SubprocessOutputCapturer:setupParentProcess()
  -- Close writing ends in parent
  C.close(self.stdout_pipe[1])
  C.close(self.stderr_pipe[1])
end

---@param onStdout fun(contents: string):nil
---@param onStderr fun(contents: string):nil
---@param onEof fun(stream_name: string):nil  -- called when a pipe reaches EOF (subprocess exited)
function SubprocessOutputCapturer:periodicallyPipeOutput(onStdout, onStderr, onEof)
  self:cancel_periodic_pipe_output()

  local task
  task = function()
    self.pollTask = nil
    self:pipeOutput(onStdout, onStderr, onEof)

    if self.stdoutEof and self.stderrEof then
      return
    end
    self.pollTask = task
    UIManager:scheduleIn(0.5, task)
  end

  self.pollTask = task
  UIManager:scheduleIn(0.5, task)
end

--- Cancels the pending poll scheduled by `periodicallyPipeOutput`, if any.
---@return nil
function SubprocessOutputCapturer:cancel_periodic_pipe_output()
  if self.pollTask then
    UIManager:unschedule(self.pollTask)
    self.pollTask = nil
  end
end

--- Closes any read descriptor that is still open. Safe to call repeatedly and
--- after `pipeOutput` already closed a stream at EOF; later `pipeOutput` calls
--- find nothing to poll.
---@return nil
function SubprocessOutputCapturer:close_pipes()
  close_fd(self.stdout_pipe, 0)
  close_fd(self.stderr_pipe, 0)
end

---@return nil
function SubprocessOutputCapturer:close_pipes_after_failed_spawn()
  close_fd(self.stdout_pipe, 0)
  close_fd(self.stderr_pipe, 0)
  close_fd(self.stdout_pipe, 1)
  close_fd(self.stderr_pipe, 1)
end

---@param onStdout fun(contents: string):nil
---@param onStderr fun(contents: string):nil
---@param onEof fun(stream_name: string):nil  -- called once per stream when its pipe reaches EOF (subprocess exited)
---@return number bytes_read Total bytes delivered to the callbacks.
function SubprocessOutputCapturer:pipeOutput(onStdout, onStderr, onEof)
  local buffer = ffi.new("char[?]", 1024)
  local fds = ffi.new("struct pollfd[2]")
  local readableEvents = bit.bor(C.POLLIN, POLLHUP)
  local total_read = 0
  local streams = {
    { name = "stdout", pipe = self.stdout_pipe, fd = self.stdout_pipe[0], onData = onStdout, eofField = "stdoutEof" },
    { name = "stderr", pipe = self.stderr_pipe, fd = self.stderr_pipe[0], onData = onStderr, eofField = "stderrEof" },
  }

  for i, stream in ipairs(streams) do
    fds[i - 1].fd = stream.fd
    fds[i - 1].events = C.POLLIN
  end

  if C.poll(fds, 2, 0) <= 0 then
    return 0
  end

  for i, stream in ipairs(streams) do
    if bit.band(fds[i - 1].revents, readableEvents) ~= 0 then
      local bytes_read = C.read(stream.fd, buffer, 1024)
      if bytes_read > 0 then
        total_read = total_read + bytes_read
        stream.onData(ffi.string(buffer, bytes_read))
      elseif bytes_read == 0 then
        close_fd(stream.pipe, 0)
        if not self[stream.eofField] then
          self[stream.eofField] = true
          if onEof then
            onEof(stream.name)
          end
        end
      end
    end
  end

  return total_read
end

util.SubprocessOutputCapturer = SubprocessOutputCapturer

return util
