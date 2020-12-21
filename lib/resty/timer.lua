--------------------------------------------------------------------------
-- Extended timer. Provides recurring, cancellable, node-wide timers, beyond
-- what the basic OpenResty timers do.
--
-- @copyright 2017 - 2020 Kong Inc.
-- @author Thijs Schreijer
-- @license Apache 2.0

local timer_at = ngx.timer.at
local pack = function(...) return { n = select("#", ...), ...} end
local _unpack = unpack or table.unpack -- luacheck: ignore
local unpack = function(t, i, j) return _unpack(t, i or 1, j or t.n or #t) end
local anchor_registry = {}
local gc_registry = setmetatable({},{ __mode = "v" })
local timer_id = 0
local now = ngx.now
local sleep = ngx.sleep
local exiting = ngx.worker.exiting

local KEY_PREFIX    = "[lua-resty-timer]"
local LOG_PREFIX    = "[resty-timer] "
local CANCEL_GC     = "GC"
local CANCEL_SYSTEM = "SYSTEM"
local CANCEL_USER   = "USER"



--- Cancel the timer.
-- Will run the 'cancel'-callback if provided. Will only cancel the timer
-- in the current worker.
-- @function timer:cancel
-- @return results of the 'cancel' callback, or `true` if no callback was provided
-- or `nil + "already cancelled"` if called repeatedly
-- @usage local t, err = resty_timer(options)  -- create a timer
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
  self.premature_reason = self.premature_reason or CANCEL_USER
  if self.cb_cancel then
    local args = self.args
    self.args = nil -- lend GC a hand
    return self.cb_cancel(self.premature_reason, unpack(args))
  end
  self.args = nil -- lend GC a hand
  return true
end



local function handler(premature, id)
  local next_interval
  while true do
    do  -- extra do-end block for local scoping and GC hand-holding
      local self = gc_registry[id] or anchor_registry[id]
      if not self then  -- timer was garbage collected exit
        return
      end

      local registry = self.detached and anchor_registry or gc_registry

      if self.cancel_flag then  -- timer was cancelled, but not yet GC'ed, exit
        return
      end

      if premature then   -- premature, so we're being cancelled by the system
        self.premature_reason = self.premature_reason or CANCEL_SYSTEM
        return self:cancel()
      end

      if not self.recurring then
        -- not recurring, so must make available for GC
        registry[id] = nil
        self.id = nil

        self.cb_expire(unpack(self.args))  -- not recurring, so no pcall required
        return
      end

      -- from here only recurring timers

      local execute = true
      if self.key_name then
        -- node wide timer, so validate we're up to run
        local ok, err = self.shm:add(self.key_name, true, self.interval - 0.001)
        if not ok then
          if err == "exists" then
            execute = false -- we're not up
          else
            ngx.log(ngx.ERR, LOG_PREFIX, "failed to add key '", self.key_name, "': ", err)
          end
        end
      end

      if execute then
        -- clear jitter on first expiry
        self.jitter = 0
        self.sub_jitter = 0
        local ok, err = xpcall(self.cb_expire, debug.traceback, unpack(self.args))
        if not ok then
          ngx.log(ngx.ERR, LOG_PREFIX, "timer callback failed with: ", tostring(err))
        end
      end

      -- calculate next interval
      local interval = self.sub_interval + self.sub_jitter
      local t = now()
      next_interval = math.max(0, self.expire + interval - t)
      self.expire = t + next_interval

      -- do we need to recycle the current timer-context?
      local call_count = self.call_count + 1
      if call_count > self.max_use then
        -- recreate context
        local ok, err = timer_at(next_interval, handler, id)
        if ok then
          self.call_count = 0
          return -- exit the while loop, and end this timer context
        end
        -- couldn't create a timer, so the system seems to be under pressure
        -- of timer resources, so we log the error and then fallback on the
        -- current context and sleeping. Next invocation will again try and
        -- replace the timer context.
        if err ~= "process exiting" then
          ngx.log(ngx.ERR, LOG_PREFIX, "failed to create timer: " .. err)
        end
      end
      self.call_count = call_count
      self = nil -- luacheck: ignore -- just to make sure we're eligible for GC
    end

    -- existing timer recurring, so keep this thread alive and just sleep
    if not exiting() then
      sleep(next_interval)
    end
    premature = exiting()
  end  -- while
end



--- Create a new timer.
-- The `opts` table is not stored nor altered, and can hence be safely reused to
-- create multiple timers. It supports the following parameters:
--
-- * `interval` : (number) interval in seconds after which the timer expires
--
-- * `recurring` : (boolean) set to `true` to make it a recurring timer
--
-- * `jitter` : (optional, number) variable interval to add to the first interval, default 0.
-- If set to 1 second then the first interval will be set between `interval` and `interval + 1`.
-- This makes sure if large numbers of timers are used, their execution gets randomly
-- distributed.
--
-- * `immediate` : (boolean) will do the first run immediately (the initial
-- interval will be set to 0 seconds). This option requires the `recurring` option.
-- The first run will not include the `jitter` interval, it will be added to second run.
--
-- * `detached` : (boolean) if set to `true` the timer will keep running detached, if
-- set to `false` the timer will be garbage collected unless anchored
-- by the user.
--
-- * `expire` : (function) callback called as `function(...)` with the arguments passed
-- as extra beyond the `opts` table to this `new` function.
--
-- * `cancel` : (optional, function) callback called as `function(reason, ...)`. Where
-- `reason` indicates why it was cancelled. The additional arguments will be the
-- arguments as passed to this `new` function, beyond the `opts` table. See the
-- usage example below for possible values for `reason`.
--
-- * `shm_name` : (optional, string) name of the shm to use to synchronize with the
-- other workers if `key_name` is set.
--
-- * `key_name` : (optional, string) key name to use in shm `shm_name`. If this key is given
-- the timer will only be executed in a single worker. All timers (across all workers) with the same
-- key will share this. The key will always be prefixed with this module's
-- name to prevent name collisions in the shm. This option requires the `shm_name` option.
--
-- * `sub_interval` : (optional, number) interval in seconds to check whether
-- the timer needs to run. Only used for cross-worker timers. This setting reduces
-- the maximum delay when a worker that currently runs the timer exits. In this case the
-- maximum delay could be `interval * 2` before another worker picks it up. With
-- this option set, the maximum delay will be `interval + sub_interval`.
-- This option requires the `immediate` and `key_name` options.
--
-- * `max_use` : (optional, number, default 1000) the maximum use count for a
-- timer context before recreating it.
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
-- function object.cancel_callback(reason, self, ...)
--   -- Note: here we cannot use colon-":" syntax, due to the 'reason' parameter
--   print("stopping ", self.name, ": ", ...)   --> "stopping myName: 1 two 3"
--   if reason == resty_timer.CANCEL_USER then
--     -- user called `timer:cancel`
--   elseif reason == resty_timer.CANCEL_GC then
--     -- the timer was garbage-collected
--   elseif reason == resty_timer.CANCEL_SYSTEM then
--     -- prematurely cancelled by the system (worker is exiting)
--   else
--     -- should not happen
--   end
-- end
--
-- function object:start()
--   if self.timer then return end
--   self.timer = resty_timer({
--     interval = 1,
--     expire = self.timer_callback,
--     cancel = self.cancel_callback,
--   }, self, 1, " two ", 3)  -- 'self' + 3 parameters to pass to the callbacks
--
-- function object:stop()
--   if self.timer then
--     self.timer:cancel()
--     self.timer = nil
--   end
-- end
local function new(opts, ...)
  local self = {
    -- timer basics
    interval = tonumber(opts.interval),    -- interval in ms
    recurring = opts.recurring,  -- should the timer be recurring?
    immediate = opts.immediate,  -- do first run immediately, at 0 seconds
    detached = opts.detached,    -- should run detached, prevent GC
    args = pack(...),            -- arguments to pass along
    jitter = opts.jitter,        -- maximum variance in each schedule
    max_use = opts.max_use,      -- max use count before recycling timer context
    -- callbacks
    cb_expire = opts.expire,     -- the callback function
    cb_cancel = opts.cancel,     -- callback function on cancellation
    -- shm info for node-wide timers
    shm = nil,                   -- the shm to use based on `opts.shm_name` (set below)
    key_name = opts.key_name,    -- unique shm key, if provided it will be a node-wide timer
    sub_interval = opts.sub_interval, -- sub_interval to use in ms
    -- methods
    cancel = cancel,             -- cancel method
    -- internal stuff
    id = nil,                    -- timer id in the registry
    cancel_flag = nil,           -- indicator timer was cancelled
    premature_reason = nil,      -- inicator why we're being cancelled
    gc_proxy = nil,              -- userdata proxy to track GC
    expire = nil,                -- time when timer expires
    call_count = 0,              -- call_count in current timer context
  }

  assert(self.interval, "expected 'interval' to be a number")
  assert(self.interval >= 0, "expected 'interval' to be greater than or equal to 0")
  assert(type(self.cb_expire) == "function", "expected 'expire' to be a function")
  if not self.recurring then
    assert(not self.immediate, "the 'immediate' option requires 'recurring'")
  end
  if self.cb_cancel then
    assert(type(self.cb_cancel) == "function", "expected 'cancel' to be a function")
    if not self.detached then
      -- add a proxy to track GC
      self.gc_proxy = newproxy(true)
      getmetatable(self.gc_proxy).__gc = function()
          self.premature_reason = self.premature_reason or CANCEL_GC
          return self:cancel()
        end
    end
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
  if self.jitter ~= nil then
    assert(type(self.jitter) == "number", "expected 'jitter' to be a number")
    assert(self.jitter >= 0, "expected 'jitter' to be greater than or equal to 0")
    self.jitter = math.random() * self.jitter
    self.sub_jitter = self.jitter * self.sub_interval / self.interval
  else
    self.jitter = 0
    self.sub_jitter = 0
  end
  if self.max_use then
    assert(self.recurring, "'max_use' can only be specified on recurring timers")
    assert(type(self.max_use) == "number", "expected 'max_use' to be a number")
    assert(self.max_use > 0, "expected 'max_use' to be greater than 0")
  else
    self.max_use = 1000
  end
  if self.key_name then
    assert(type(self.key_name) == "string", "expected 'key_name' to be a string")
    assert(opts.shm_name, "'shm_name' is required when specifying 'key_name'")
    self.shm = ngx.shared[opts.shm_name]
    assert(self.shm, "shm by name '" .. tostring(opts.shm_name) .. "' not found")
    self.key_name = KEY_PREFIX .. self.key_name
  end

  -- create the actual timer
  timer_id = timer_id + 1
  local interval = self.sub_interval + self.sub_jitter
  interval = self.immediate and 0 or interval

  local ok, err = timer_at(interval, handler, timer_id)
  if ok then
    local registry = self.detached and anchor_registry or gc_registry
    registry[timer_id] = self
    self.id = timer_id
    self.expire = now() + interval
  else
    ngx.log(ngx.ERR, LOG_PREFIX, "failed to create timer: " .. err)
  end
  return ok and self or ok, err
end



return setmetatable(
  {
    new = new,
    CANCEL_GC = CANCEL_GC,
    CANCEL_SYSTEM = CANCEL_SYSTEM,
    CANCEL_USER = CANCEL_USER,
--    __anchor = anchor_registry,   -- for test purposes
--    __gc = gc_registry,           -- for test purposes
  }, {
    __call = function(self, ...) return new(...) end,
  }
)
