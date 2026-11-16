local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local Trapper = require("ui/trapper")
local _ = require("gettext+")
local Backend = require("Backend")
local ffi = require("ffi")
local bit = require("bit")
require("ffi/posix_h")

-- register shared memory for tracking progress
pcall(ffi.cdef, [[
  typedef struct {
    int processed;
    int total;
    int updated;
  } ko_progress_shm_t;
  void *mmap(void *addr, size_t length, int prot, int flags, int fd, long offset);
  int munmap(void *addr, size_t length);
]])

local C = ffi.C

local LoadingDialog = {}

--- Wraps a function so that, when it runs in the forked subprocess, `Backend` leaves restarting
--- a lost backend to this module (running in the parent process) instead of doing it itself.
--- @generic T: any
--- @param runnable fun(...): T
--- @return fun(...): T
local function asBackendWorker(runnable)
  return function(...)
    Backend.clearRecoveryRequest()
    Backend.markAsWorkerProcess()
    local results = table.pack(runnable(...))
    table.insert(results, 1, Backend.recoveryRequired())
    results.n = results.n + 1
    return unpack(results, 1, results.n)
  end
end

local function showTaskDialog(message, onCancel, onConfirmCancel, onSetCancelled)
  local dialog
  local confirmCancelDialog
  local function handleCancel()
    local cancel = function()
      onSetCancelled(true)
      if onCancel ~= nil then
        onCancel()
      end
    end
    if onConfirmCancel ~= nil then
      confirmCancelDialog = onConfirmCancel(cancel)
    else
      cancel()
    end
  end

  local function createDialog(text)
    dialog = onCancel == nil and InfoMessage:new {
      text = text,
      dismissable = false,
    } or ConfirmBox:new {
      text = text,
      icon = "notice-info",
      no_ok_button = true,
      -- dismissable = false,
      cancel_callback = function()
        if dialog.dismiss_callback then
          dialog.dismiss_callback()
        else
          handleCancel()
        end
      end
    }
    return dialog
  end

  createDialog(message)
  UIManager:show(dialog)
  UIManager:forceRePaint()

  return {
    get = function()
      return dialog
    end,
    set = function(text)
      UIManager:close(dialog)
      createDialog(text)
      UIManager:show(dialog)
      UIManager:forceRePaint()
    end,
    getConfirmCancel = function()
      return confirmCancelDialog
    end,
  }
end

--- Shows a message in a info dialog, while running the given `runnable` function.
--- Must be called from inside a function wrapped with `Trapper:wrap()`.
---
--- @generic T: any
--- @param message string The message to be shown on the dialog.
--- @param runnable fun(): T The function to be ran while showing the dialog.
--- @param onCancel fun()?: T An optional function to be called if the dialog is dismissed/cancelled.
--- @param onConfirmCancel (fun(any): any) | nil
--- @param onRecovery fun()?: nil Reset backend-owned state before a recovery retry.
--- @return T, boolean
function LoadingDialog:showAndRun(message, runnable, onCancel, onConfirmCancel, onRecovery)
  assert(Trapper:isWrapped(), "expected to be called inside a function wrapped with `Trapper:wrap()`")

  local cancelled = false
  local dialogRef = showTaskDialog(message, onCancel, onConfirmCancel, function(value)
    cancelled = value
  end)
  local message_dialog = dialogRef.get()

  local completed, recovery_required, return_values =
      Trapper:dismissableRunInSubprocess(asBackendWorker(runnable), message_dialog)
  if completed and not cancelled and recovery_required then
    -- The subprocess lost the backend, but only this process can replace `Backend.server`.
    Backend.restart()
    if onRecovery ~= nil then
      onRecovery()
    end
    completed, _, return_values =
        Trapper:dismissableRunInSubprocess(asBackendWorker(runnable), message_dialog)
  end

  if onCancel == nil then
    assert(completed, "Expected runnable to run to completion")
  end

  local confirmCancel = dialogRef.getConfirmCancel()
  if confirmCancel ~= nil then
    UIManager:close(confirmCancel)
  end
  UIManager:close(message_dialog)

  return return_values, cancelled
end

local function allocateProgressShm()
  local shm_size = ffi.sizeof("ko_progress_shm_t")
  local raw_shm = C.mmap(nil, shm_size, bit.bor(C.PROT_READ, C.PROT_WRITE), bit.bor(C.MAP_SHARED, C.MAP_ANONYMOUS), -1, 0)

  if raw_shm == ffi.cast("void *", -1) then
    error("can't allocate shared memory")
  end

  local shm = ffi.cast("ko_progress_shm_t *", raw_shm)
  shm.processed = 0
  shm.total = 0
  shm.updated = 0

  return { raw_shm = raw_shm, shm = shm, shm_size = shm_size }
end

local function scheduleProgressPoll(shm, message, getDialog, setDialog, lastTextRef)
  local poll_action
  poll_action = function()
    -- If child process signals a new update (updated == 1)
    if shm.updated == 1 then
      local processed = shm.processed
      local total = shm.total

      if total > 0 then
        local percentage = math.floor(processed / total * 100)
        local new_text = message .. "\n\n" .. percentage .. "% (" .. processed .. "/" .. total .. ")"

        if new_text ~= lastTextRef.text then
          lastTextRef.text = new_text
          local current_dismiss_cb = getDialog().dismiss_callback

          setDialog(new_text)

          getDialog().dismiss_callback = current_dismiss_cb
        end
      end
      -- reset update flag for next update from child
      shm.updated = 0
    end
    UIManager:scheduleIn(0.1, poll_action)
  end

  UIManager:scheduleIn(0.1, poll_action)

  return poll_action
end

local function createProgressTask(runnable, shm)
  return function()
    local child_progress = function(progress)
      if not progress or progress.type ~= 'DOWNLOADING' then return end
      -- child process writes directly to shared RAM
      shm.processed = progress.processed
      shm.total = progress.total
      shm.updated = 1
    end
    return runnable(child_progress)
  end
end

local function runWorkerWithRecovery(task, message_dialog, onRecovery)
  local results = table.pack(Trapper:dismissableRunInSubprocess(asBackendWorker(task), message_dialog, false))
  if results[1] and results[2] then
    -- The subprocess lost the backend, but only this process can replace `Backend.server`.
    Backend.restart()
    if onRecovery ~= nil then
      onRecovery()
    end
    results = table.pack(Trapper:dismissableRunInSubprocess(asBackendWorker(task), message_dialog, false))
  end
  return results
end

local function finishProgressTask(progress, message_dialog, getConfirmCancel, poll_action, onCancel, onSetCancelled, completed)
  UIManager:unschedule(poll_action)
  C.munmap(progress.raw_shm, progress.shm_size)

  if not completed then
    onSetCancelled(true)
    if onCancel ~= nil then
      onCancel()
    end
  end

  if onCancel == nil then
    assert(completed, "Expected runnable to run to completion")
  end

  local confirmCancel = getConfirmCancel()
  if confirmCancel ~= nil then
    UIManager:close(confirmCancel)
  end
  UIManager:close(message_dialog)
end

--- Shows a message with progress updates in a dialog, while running the given `runnable` function.
--- Must be called from inside a function wrapped with `Trapper:wrap()`.
---
--- @generic T: any
--- @param message string The message to be shown on the dialog.
--- @param runnable fun(onProgress: fun(progress: { type: string, processed: number?, total: number? })): T The function to be ran while showing the dialog. Receives a callback to report progress.
--- @param onCancel fun()?: T An optional function to be called if the dialog is dismissed/cancelled.
--- @param onConfirmCancel (fun(any): any) | nil
--- @param onRecovery fun()?: nil Reset backend-owned state before a recovery retry.
--- @return T, boolean
function LoadingDialog:showAndRunWithProgress(message, runnable, onCancel, onConfirmCancel, onRecovery)
  assert(Trapper:isWrapped(), "expected to be called inside a function wrapped with `Trapper:wrap()`")

  local cancelled = false
  local dialogRef = showTaskDialog(message, onCancel, onConfirmCancel, function(value)
    cancelled = value
  end)

  local progress = allocateProgressShm()
  local shm = progress.shm

  local last_text = { text = message }
  local poll_action = scheduleProgressPoll(shm, message, dialogRef.get, dialogRef.set, last_text)

  local trapper_results =
      runWorkerWithRecovery(createProgressTask(runnable, shm), dialogRef.get(), onRecovery)

  local completed = trapper_results[1]
  finishProgressTask(progress, dialogRef.get(), dialogRef.getConfirmCancel, poll_action, onCancel, function(value)
    cancelled = value
  end, completed)

  if completed then
    return unpack(trapper_results, 3, trapper_results.n), cancelled
  else
    return nil, cancelled
  end
end

--- @param message string The message to be shown on the dialog.
--- @param onCancel fun()?: T An optional function to be called if the dialog is dismissed/cancelled.
--- @param onConfirmCancel (fun(any): any)?
--- @diagnostic disable-next-line: undefined-doc-name
--- @return InfoMessage|ConfirmBox, InfoMessage|ConfirmBox|nil
function LoadingDialog:simple(message, onCancel, onConfirmCancel)
  local conConfirmCancel = nil
  local message_dialog = onCancel == nil and InfoMessage:new {
    text = message,
    dismissable = false,
  } or ConfirmBox:new {
    text = message,
    icon = "notice-info",
    no_ok_button = true,
    dismissable = false,
    cancel_callback = function()
      local cancel = function()
        if onCancel ~= nil then
          onCancel()
        end
      end

      if onConfirmCancel ~= nil then
        conConfirmCancel = onConfirmCancel(cancel)
      else
        cancel()
      end
    end
  }

  UIManager:show(message_dialog)

  return message_dialog, conConfirmCancel
end

return LoadingDialog
