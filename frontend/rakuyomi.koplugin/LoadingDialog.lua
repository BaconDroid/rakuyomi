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
local function as_backend_worker(runnable)
  return function(...)
    Backend.clear_recovery_request()
    Backend.mark_as_worker_process()
    local results = table.pack(runnable(...))
    table.insert(results, 1, Backend.recovery_required())
    results.n = results.n + 1
    return unpack(results, 1, results.n)
  end
end

local function show_task_dialog(message, onCancel, onConfirmCancel, on_set_cancelled)
  local dialog
  local confirm_cancel_dialog
  local cancel_handled = false
  local function cancel_once()
    if cancel_handled then
      return
    end
    cancel_handled = true
    on_set_cancelled(true)
    if dialog ~= nil and dialog.dismiss_callback ~= nil then
      local dismiss_cb = dialog.dismiss_callback
      dialog.dismiss_callback = nil
      dismiss_cb()
    end
    if onCancel ~= nil then
      onCancel()
    end
  end
  local function handle_cancel()
    if cancel_handled then
      return
    end
    if onConfirmCancel ~= nil then
      confirm_cancel_dialog = onConfirmCancel(cancel_once)
      local confirm = confirm_cancel_dialog
      if confirm ~= nil then
        local orig_on_close = confirm.onCloseWidget
        confirm.onCloseWidget = function(self)
          if confirm_cancel_dialog == self then
            confirm_cancel_dialog = nil
          end
          if orig_on_close ~= nil then
            orig_on_close(self)
          end
        end
      end
    else
      cancel_once()
    end
  end

  local function create_dialog(text)
    dialog = onCancel == nil and InfoMessage:new {
      text = text,
      dismissable = false,
    } or ConfirmBox:new {
      text = text,
      icon = "notice-info",
      no_ok_button = true,
      cancel_callback = function()
        handle_cancel()
      end
    }
    return dialog
  end

  create_dialog(message)
  UIManager:show(dialog)
  UIManager:forceRePaint()

  return {
    get = function()
      return dialog
    end,
    set = function(text)
      if confirm_cancel_dialog ~= nil then
        return false
      end
      local dismiss_cb = dialog.dismiss_callback
      dialog.dismiss_callback = nil
      UIManager:close(dialog)
      create_dialog(text)
      dialog.dismiss_callback = dismiss_cb
      UIManager:show(dialog)
      UIManager:forceRePaint()
      return true
    end,
    get_confirm_cancel = function()
      return confirm_cancel_dialog
    end,
    cancel_once = cancel_once,
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
--- @return T, boolean
function LoadingDialog:showAndRun(message, runnable, onCancel, onConfirmCancel)
  assert(Trapper:isWrapped(), "expected to be called inside a function wrapped with `Trapper:wrap()`")

  local cancelled = false
  local dialog_ref = show_task_dialog(message, onCancel, onConfirmCancel, function(value)
    cancelled = value
  end)
  local message_dialog = dialog_ref.get()

  local completed, recovery_required, return_values =
      Trapper:dismissableRunInSubprocess(as_backend_worker(runnable), message_dialog)
  if completed and not cancelled and recovery_required then
    Backend.restart()
  end

  if onCancel == nil then
    assert(completed, "Expected runnable to run to completion")
  end

  local confirm_cancel = dialog_ref.get_confirm_cancel()
  if confirm_cancel ~= nil then
    UIManager:close(confirm_cancel)
  end
  UIManager:close(message_dialog)

  return return_values, cancelled
end

local function allocate_progress_shm()
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

local function schedule_progress_poll(shm, message, set_dialog, last_text_ref)
  local poll_action
  poll_action = function()
    -- If child process signals a new update (updated == 1)
    if shm.updated == 1 then
      local processed = shm.processed
      local total = shm.total
      local applied = true

      if total > 0 then
        local percentage = math.floor(processed / total * 100)
        local new_text = message .. "\n\n" .. percentage .. "% (" .. processed .. "/" .. total .. ")"

        if new_text ~= last_text_ref.text then
          applied = set_dialog(new_text)
          if applied then
            last_text_ref.text = new_text
          end
        end
      end

      if applied then
        -- reset update flag for next update from child
        shm.updated = 0
      end
    end
    UIManager:scheduleIn(0.1, poll_action)
  end

  UIManager:scheduleIn(0.1, poll_action)

  return poll_action
end

local function create_progress_task(runnable, shm)
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

local function run_worker_with_recovery(task, message_dialog, is_cancelled)
  local results = table.pack(Trapper:dismissableRunInSubprocess(as_backend_worker(task), message_dialog, false))
  if results[1] and results[2] and not (is_cancelled ~= nil and is_cancelled()) then
    Backend.restart()
  end
  return results
end

local function finish_progress_task(progress, message_dialog, get_confirm_cancel, poll_action, cancel_once, onCancel, completed)
  UIManager:unschedule(poll_action)
  C.munmap(progress.raw_shm, progress.shm_size)

  if not completed then
    cancel_once()
  end

  if onCancel == nil then
    assert(completed, "Expected runnable to run to completion")
  end

  local confirm_cancel = get_confirm_cancel()
  if confirm_cancel ~= nil then
    UIManager:close(confirm_cancel)
  end
  UIManager:close(message_dialog)
end

--- Shows a message with progress updates in a dialog, while running the given `runnable` function.
--- Must be called from inside a function wrapped with `Trapper:wrap()`.
--- @generic T: any
--- @param message string The message to be shown on the dialog.
--- @param runnable fun(onProgress: fun(progress: { type: string, processed: number?, total: number? })): T The function to be ran while showing the dialog. Receives a callback to report progress.
--- @param onCancel fun()?: T An optional function to be called if the dialog is dismissed/cancelled.
--- @param onConfirmCancel (fun(any): any) | nil
--- @return T, boolean
function LoadingDialog:showAndRunWithProgress(message, runnable, onCancel, onConfirmCancel)
  assert(Trapper:isWrapped(), "expected to be called inside a function wrapped with `Trapper:wrap()`")

  local cancelled = false
  local progress = allocate_progress_shm()
  local dialog_ok, dialog_ref = pcall(show_task_dialog, message, onCancel, onConfirmCancel, function(value)
    cancelled = value
  end)
  if not dialog_ok then
    C.munmap(progress.raw_shm, progress.shm_size)
    error(dialog_ref)
  end

  local shm = progress.shm

  local last_text = { text = message }
  local poll_action = schedule_progress_poll(shm, message, dialog_ref.set, last_text)

  local trapper_results =
      run_worker_with_recovery(create_progress_task(runnable, shm), dialog_ref.get(), function()
        return cancelled
      end)

  local completed = trapper_results[1]
  finish_progress_task(progress, dialog_ref.get(), dialog_ref.get_confirm_cancel, poll_action, dialog_ref.cancel_once, onCancel, completed)

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
