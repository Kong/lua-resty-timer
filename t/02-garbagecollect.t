use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

workers(1);

plan tests => repeat_each() * (blocks() * 2);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_shared_dict test_shm 8m;
    lua_shared_dict timer_shm 8m;
};

run_tests();

__DATA__

=== TEST 1: new() timer gets GC'ed
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local external_count = 0
            local cancel_reason = nil
            local object = {  -- create some object with a timer
                count = 0,
                handler = function(self)
                    self.count = self.count + 1
                    external_count = self.count
                end,
                timer = nil, -- to be set below
                name = "just-a-timer",
            }
            local options = {
                interval = 0.1,
                recurring = true,
                immediate = false,
                detached = false,
                expire = object.handler,  -- insert our object based handler
                --shm_name = "timer_shm",
                --key_name = "my_key",
                cancel = function(reason, object)
                    cancel_reason = object.name .. " GC'ed? " ..
                        tostring(reason == timer.CANCEL_GC)
                end,
            }
            -- now add to object, but also pass along object !!
            object.timer = timer(options, object)
            object = nil  -- drop the object
            collectgarbage()
            collectgarbage()
            ngx.sleep(0.55)  -- could be 5 occurences
            ngx.say(external_count, cancel_reason)
        }
    }
--- request
GET /t
--- response_body
0just-a-timer GC'ed? true



=== TEST 2: new() detached timer doesn't get GC'ed in object setting
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local external_count = 0
            local object = {  -- create some object with a timer
                count = 0,
                handler = function(self)
                    self.count = self.count + 1
                    external_count = self.count
                end,
                timer = nil, -- to be set below
            }
            local options = {
                interval = 0.1,
                recurring = true,
                immediate = false,
                detached = true,
                expire = object.handler,  -- insert our object based handler
                --shm_name = "timer_shm",
                --key_name = "my_key",
            }
            -- now add to object, but also pass along object !!
            object.timer = timer(options, object)
            local testtable = setmetatable(
                {
                    timer = object.timer
                }, {
                    __mode = "v"
                })
            object = nil  -- drop the object
            collectgarbage()
            collectgarbage()
            ngx.sleep(0.55)  -- could be 5 occurences
            ngx.say(external_count)
        }
    }
--- request
GET /t
--- response_body
5



=== TEST 3: new() non-recurring timer gets GC'ed when done, even when detached
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local external_count = 0
            local object = {  -- create some object with a timer
                count = 0,
                handler = function(self)
                    self.count = self.count + 1
                    external_count = self.count
                end,
                timer = nil, -- to be set below
            }
            local options = {
                interval = 0.1,
                recurring = false,
                immediate = false,
                detached = true,
                expire = object.handler,  -- insert our object based handler
                --shm_name = "timer_shm",
                --key_name = "my_key",
            }
            -- now add to object, but also pass along object !!
            object.timer = timer(options, object)
            local testtable = setmetatable(
                {
                    timer = object.timer
                }, {
                    __mode = "v"
                })
            object = nil      -- drop the object
            ngx.sleep(0.55)   -- could be 5 occurences
            collectgarbage()
            collectgarbage()
            ngx.say(external_count .. ":" .. tostring(not testtable.timer))
        }
    }
--- request
GET /t
--- response_body
1:true



=== TEST 4: new() non-recurring, detached timer gets GC'ed when cancelled before being done
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local external_count = 0
            local object = {  -- create some object with a timer
                count = 0,
                handler = function(self)
                    self.count = self.count + 1
                    external_count = self.count
                end,
                timer = nil, -- to be set below
            }
            local options = {
                interval = 0.1,
                recurring = false,
                immediate = false,
                detached = true,
                expire = object.handler,  -- insert our object based handler
                --shm_name = "timer_shm",
                --key_name = "my_key",
            }
            -- now add to object, but also pass along object !!
            object.timer = timer(options, object)
            local testtable = setmetatable(
                {
                    timer = object.timer
                }, {
                    __mode = "v"
                })
            object.timer:cancel()   -- cancel time before it expires
            object = nil            -- drop the object
            ngx.sleep(0.55)         -- could be 5 occurences
            collectgarbage()
            collectgarbage()
            ngx.say(external_count .. ":" .. tostring(not testtable.timer))
        }
    }
--- request
GET /t
--- response_body
0:true



=== TEST 5: new() timer gets GC'ed without need to expire
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local external_count = 0
            local cancel_reason = nil
            local object = {  -- create some object with a timer
                count = 0,
                handler = function(self)
                    self.count = self.count + 1
                    external_count = self.count
                end,
                timer = nil, -- to be set below
                name = "just-a-timer",
            }
            local options = {
                interval = 0.1,
                recurring = true,
                immediate = false,
                detached = false,
                expire = object.handler,  -- insert our object based handler
                --shm_name = "timer_shm",
                --key_name = "my_key",
                cancel = function(reason, object)
                    cancel_reason = object.name .. " GC'ed? " ..
                        tostring(reason == timer.CANCEL_GC)
                end,
            }
            -- now add to object, but also pass along object !!
            object.timer = timer(options, object)
            object = nil  -- drop the object
            collectgarbage()
            collectgarbage()
            --ngx.sleep(0.55)  -- could be 5 occurences, but for this test we're
            -- not waiting, just GC calling should be enough to cancel it.
            ngx.say(external_count, cancel_reason)
        }
    }
--- request
GET /t
--- response_body
0just-a-timer GC'ed? true



=== TEST 6: new() timer gets GC'ed without expiring, and without cancel callback
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local external_count = 0
            local cancel_reason = nil
            local object = {  -- create some object with a timer
                count = 0,
                handler = function(self)
                    self.count = self.count + 1
                    external_count = self.count
                end,
                timer = nil, -- to be set below
                name = "just-a-timer",
            }
            local options = {
                interval = 0.1,
                recurring = true,
                immediate = false,
                detached = false,
                expire = object.handler,  -- insert our object based handler
                --shm_name = "timer_shm",
                --key_name = "my_key",
                --cancel = function(reason, object)
                --    cancel_reason = object.name .. " GC'ed? " ..
                --        tostring(reason == timer.CANCEL_GC)
                --end,
            }
            -- now add to object, but also pass along object !!
            object.timer = timer(options, object)

            -- create a table to track GC'ing both objects
            local tracker = setmetatable({}, { __mode = "k" })
            tracker[object] = "object"
            tracker[timer] = "timer"

            object = nil  -- drop the object
            collectgarbage()
            collectgarbage()
            --ngx.sleep(0.55)  -- could be 5 occurences, but for this test we're
            -- not waiting, just GC calling should be enough to cancel it.

            ngx.say(tracker.object and "object not collected" or "object gone")
            ngx.say(tracker.timer and "timer not collected" or "timer gone")
        }
    }
--- request
GET /t
--- response_body
object gone
timer gone
