--------------------------------------------------------------------------
-- Extended timer.
--
-- @copyright 2017 Kong Inc.
-- @author Thijs Schreijer
-- @license Apache 2.0

local timer_at = ngx.timer.at
local pack = function(...) return { n = select("#", ...), ...} end
local _unpack = unpack or table.unpack
local unpack = function(t, i, j) return _unpack(t, i or 1, j or t.n, #t) end
local anchor_registry = {}
local gc_registry = setmetatable({},{ __mode = "v" })
local timer_id = 0
local KEY_PREFIX = "[lua-resty-timer]"

--- Cancel the timer.
-- Will run the 'cancel'-callback if provided. Will only cancel the timer
-- in the current worker.
-- @function timer:cancel
-- @return results of the 'cancel' callback, or `true` if no callback was provided
-- or `nil + "already cancelled"` if called repeatedly
-- @usage local t, err = timer(options)  -- create a timer
-- if t then
--   t:cancel()  -- immediately cancel the timer again
-- end
local function cancel(self)
  if self.cancel_flag then
    return nil, "already cancelled"
  end

  local registry = self.detached and anchor_registry or gc_registry
  if self.id then
    registry[self.id] = nil
    self.id = nil
  end

  self.cancel_flag = true
  if self.cb_cancel then
    return self.cb_cancel(self.premature_flag, unpack(self.args))
  end
  return true
end

local handler = function(premature, timer_id)
  local self = gc_registry[timer_id] or anchor_registry[timer_id]
  if not self then  -- timer was garbage collected exit
    return
  end

  local registry = self.detached and anchor_registry or gc_registry

  if self.cancel_flag then  -- timer was cancelled, but not yet GC'ed, exit
    return
  end

  if premature then   -- premature, so we're being cancelled by the system
    self.premature_flag = true
    return self:cancel()
  end

  if self.recurring then
    self:schedule() -- no error checking required
  else
    -- not recurring, so must make available for GC
    registry[timer_id] = nil
    self.timer_id = nil
  end

  if self.key_name then
    -- node wide timer, so validate we're up to run
    local ok, err = self.shm:add(self.key_name, true, self.interval - 0.001)
    if not ok then
      if err == "exists" then
        return -- we're not up
      end
      ngx.log(ngx.ERR, "failed to add key '", self.key_name, "': ", err)
    end
  end

  self.cb_expire(unpack(self.args)) -- already rescheduled, so no pcall required
end

local function schedule(self)
  local interval = self.sub_interval
  local id = self.id
  if not id then
    timer_id = timer_id + 1
    id = timer_id
    self.id = id
    interval = self.immediate and 0 or interval
  end

  local registry = self.detached and anchor_registry or gc_registry

  local ok, err = timer_at(interval, handler, id)
  if ok then
    registry[id] = self
  else
    ngx.log(ngx.ERR, "failed to create timer: " .. err)
  end
  return ok and self or ok, err
end

--- Create a new timer.
-- The `opts` table supports the following parameters:
--
-- * `interval` : (number) interval in milliseconds after which the timer expires
--
-- * `recurring` : (boolean) set to `true` to make it a recurring timer
--
-- * `immediate` : (boolean) will do the first run immediately (the initial
-- interval will be set to 0 seconds). This option requires the `recurring` option.
--
-- * `detached` : (boolean) if set to `true` the timer will keep running detached, if
-- set to `false` the timer will be garbage collected unless anchored
-- by the user.
--
-- * `expire` : (function) callback called as `function(...)` with the arguments passed
-- as extra beyond the `opts` table to this `new` function.
--
-- * `cancel` : (optional, function) callback called as `function(premature, ...)`. Where
-- `premature` is the flag indicating that the timer is cancelled by the
-- system, see `ngx.timer.at` documentation. The additional arguments will be the
-- arguments as passed to this `new` function, beyond the `opts` table.</br>
-- *NOTE*: will be called when cancelled by the user or the system, but *not* when
-- garbage collected.
--
-- * `shm_name` : (optional, string) name of the shm to use to synchronize with the
-- other workers if `key_name` is set.
--
-- * `key_name` : (optional, string) key name to use in shm `shm_name`. If this key is given
-- the timer will only be executed in a single worker. All timers (across all workers) with the same
-- key will share this. The key will always be prefixed with this module's
-- name to prevent name collissions in the shm. This option requires the `shm_name` option.
--
-- * `sub_interval` : (optional, number) interval in milliseconds to check wether
-- the timer needs to run. Only used for cross-worker timers. This setting reduces
-- the maximum delay when a worker that currently runs the timer exits. In this case the
-- maximum delay could be `interval * 2` before another worker picks it up. With
-- this option set, the maximum delay will be `interval + sub_interval`.
-- This option requires the `immediate` and `key_name` options.
--
-- @function new
-- @param opts table with options
-- @param ... arguments to pass to the callbacks `expire` and `cancel`.
-- @return `timer` object or `nil + err`
-- @usage
-- local object = {
--   name = "myName",
-- }
-- 
-- function object:timer_callback(...)
--   -- Note: here we use colon-":" syntax
--   print("starting ", self.name, ": ", ...)   --> "starting myName: 1 two 3"
-- end
--
-- function object.cancel_callback(premature, self, ...)
--   -- Note: here we cannot use colon-":" syntax, due to the 'premature' parameter
--   print("stopping ", self.name, ": ", ...)   --> "stopping myName: 1 two 3"
-- end
--
-- function object:start()
--   if self.timer then return end
--   self.timer = timer({
--     interval = 1000,
--     expire = self.timer_callback,
--     cancel = self.cancel_callback,
--   }, self, 1, " two ", 3)  -- 'self' + 3 parameters to pass to the callbacks
--
-- function object:stop()
--   if not self.timer then return end
--   self.timer:cancel()
-- end
local function new(opts, ...)
  local self = {
    -- timer basics
    interval = tonumber(opts.interval),    -- interval in ms
    recurring = opts.recurring,  -- should the timer be recurring?
    immediate = opts.immediate,  -- do first run immediately, at 0 seconds
    detached = opts.detached,    -- should run detached, prevent GC
    args = pack(...),            -- arguments to pass along
    -- callbacks
    cb_expire = opts.expire,     -- the callback function
    cb_cancel = opts.cancel,     -- callback function on cancellation
    -- shm info for node-wide timers
    shm = nil,                   -- the shm to use based on `opts.shm_name` (set below)
    key_name = opts.key_name,    -- unique shm key, if provided it will be a node-wide timer
    sub_interval = opts.sub_interval, -- sub_interval to use in ms
    -- methods
    cancel = cancel,             -- cancel method
    schedule = schedule,         -- schedule method
    -- internal stuff
    id = nil,                    -- timer id in the registry
    cancel_flag = nil,           -- indicator timer was cancelled
    premature_flag = nil,        -- inicator we're being cancelled by the system
  }

  assert(self.interval, "expected 'interval' to be a number")
  assert(self.interval >= 0, "expected 'interval' to be greater than or equal to 0")
  assert(type(self.cb_expire) == "function", "expected 'expire' to be a function")
  if not self.recurring then
    assert(not self.immediate, "the 'immediate' option requires 'recurring'")
  end
  if self.cb_cancel then
    assert(type(self.cb_cancel) == "function", "expected 'cancel' to be a function")
  end
  if self.sub_interval then
    self.sub_interval = tonumber(self.sub_interval)
    assert(self.sub_interval, "expected 'sub_interval' to be a number")
    assert(self.key_name, "'key_name' is required when specifying 'sub_interval'")
    assert(self.immediate, "'immediate' is required when specifying 'sub_interval'")
    assert(self.sub_interval >= 0, "expected 'sub_interval' to be greater than or equal to 0")
    assert(self.sub_interval <= self.interval, "expected 'sub_interval' to be less than or equal to 'interval'")
  else
    self.sub_interval = self.interval
  end
  if self.key_name then
    assert(type(self.key_name) == "string", "expected 'key_name' to be a string")
    assert(opts.shm_name, "'shm_name' is required when specifying 'key_name'")
    self.shm = ngx.shared[opts.shm_name]
    assert(self.shm, "shm by name '" .. tostring(opts.shm_name) .. "' not found")
    self.key_name = KEY_PREFIX .. self.key_name
  end

  return self:schedule()
end

return setmetatable(
  { 
    new = new,
--    __anchor = anchor_registry,   -- for test purposes
--    __gc = gc_registry,           -- for test purposes
  }, {
    __call = function(self, ...) return new(...) end,
  }
)
