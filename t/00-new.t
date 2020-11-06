use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

workers(1);

plan tests => repeat_each() * (blocks() * 3) - 3;

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_shared_dict test_shm 8m;
    lua_shared_dict timer_shm 8m;
};

run_tests();

__DATA__

=== TEST 1: new() works with valid input
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local options = {
                interval = 0.1,
                recurring = true,
                immediate = false,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "EXPIRE ", arg1, arg2, arg3)
                end,
                cancel = function(reason, arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "CANCEL ", reason, arg1, arg2, arg3)
                end,
                shm_name = "timer_shm",
                key_name = "my_key",
                --sub_interval = 0.1,
            }
            local ok, err = pcall(timer.new, options, "arg1", nil, "arg3")
            if ok then
                ngx.say(true)
            else
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body
true
--- error_log



=== TEST 2: new() requires interval as positive number
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local options = {
                interval = -1,
                recurring = true,
                immediate = false,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "EXPIRE ", arg1, arg2, arg3)
                end,
                cancel = function(reason, arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "CANCEL ", reason, arg1, arg2, arg3)
                end,
                shm_name = "timer_shm",
                key_name = "my_key",
                sub_interval = 0.1,
            }
            local ok, err = pcall(timer.new, options, "arg1", nil, "arg3")
            if ok then
                ngx.say(true)
            else
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
expected 'interval' to be greater than or equal to 0



=== TEST 3: new() requires interval as number
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local options = {
                interval = "xxx",
                recurring = true,
                immediate = false,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "EXPIRE ", arg1, arg2, arg3)
                end,
                cancel = function(reason, arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "CANCEL ", reason, arg1, arg2, arg3)
                end,
                shm_name = "timer_shm",
                key_name = "my_key",
                sub_interval = 0.1,
            }
            local ok, err = pcall(timer.new, options, "arg1", nil, "arg3")
            if ok then
                ngx.say(true)
            else
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
expected 'interval' to be a number



=== TEST 4: new() expire callback must be a function
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local options = {
                interval = 1,
                recurring = true,
                immediate = false,
                detached = false,
                expire = "string",
                cancel = function(reason, arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "CANCEL ", reason, arg1, arg2, arg3)
                end,
                shm_name = "timer_shm",
                key_name = "my_key",
                sub_interval = 0.1,
            }
            local ok, err = pcall(timer.new, options, "arg1", nil, "arg3")
            if ok then
                ngx.say(true)
            else
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
expected 'expire' to be a function



=== TEST 5: new() cancel is not required
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local options = {
                interval = 1,
                recurring = true,
                immediate = false,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "EXPIRE ", arg1, arg2, arg3)
                end,
                --cancel = function(reason, arg1, arg2, arg3)
                --    ngx.log(ngx.ERR, "CANCEL ", reason, arg1, arg2, arg3)
                --end,
                shm_name = "timer_shm",
                key_name = "my_key",
                --sub_interval = 0.1,
            }
            local ok, err = pcall(timer.new, options, "arg1", nil, "arg3")
            if ok then
                ngx.say(true)
            else
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body
true
--- error_log



=== TEST 6: new() cancel must be a function
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local options = {
                interval = 1,
                recurring = true,
                immediate = false,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "EXPIRE ", arg1, arg2, arg3)
                end,
                cancel = "string",
                shm_name = "timer_shm",
                key_name = "my_key",
                sub_interval = 0.1,
            }
            local ok, err = pcall(timer.new, options, "arg1", nil, "arg3")
            if ok then
                ngx.say(true)
            else
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
expected 'cancel' to be a function



=== TEST 7: new() key_name is not required
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local options = {
                interval = 1,
                recurring = true,
                immediate = false,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "EXPIRE ", arg1, arg2, arg3)
                end,
                cancel = function(reason, arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "CANCEL ", reason, arg1, arg2, arg3)
                end,
                shm_name = "timer_shm",
                --key_name = "my_key",
                --sub_interval = 0.1,
            }
            local ok, err = pcall(timer.new, options, "arg1", nil, "arg3")
            if ok then
                ngx.say(true)
            else
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body
true
--- error_log



=== TEST 8: new() key_name must be a string
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local options = {
                interval = 1,
                recurring = true,
                immediate = false,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "EXPIRE ", arg1, arg2, arg3)
                end,
                cancel = function(reason, arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "CANCEL ", reason, arg1, arg2, arg3)
                end,
                shm_name = "timer_shm",
                key_name = 0,
                --sub_interval = 0.1,
            }
            local ok, err = pcall(timer.new, options, "arg1", nil, "arg3")
            if ok then
                ngx.say(true)
            else
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
expected 'key_name' to be a string



=== TEST 9: new() shm_name required when key_name is given
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local options = {
                interval = 1,
                recurring = true,
                immediate = false,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "EXPIRE ", arg1, arg2, arg3)
                end,
                cancel = function(reason, arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "CANCEL ", reason, arg1, arg2, arg3)
                end,
                --shm_name = "timer_shm",
                key_name = "my_key",
                --sub_interval = 0.1,
            }
            local ok, err = pcall(timer.new, options, "arg1", nil, "arg3")
            if ok then
                ngx.say(true)
            else
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
'shm_name' is required when specifying 'key_name'



=== TEST 10: new() shm must exist
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local options = {
                interval = 1,
                recurring = true,
                immediate = false,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "EXPIRE ", arg1, arg2, arg3)
                end,
                cancel = function(reason, arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "CANCEL ", reason, arg1, arg2, arg3)
                end,
                shm_name = "non-existing",
                key_name = "my_key",
                --sub_interval = 0.1,
            }
            local ok, err = pcall(timer.new, options, "arg1", nil, "arg3")
            if ok then
                ngx.say(true)
            else
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
shm by name 'non-existing' not found



=== TEST 11: new() cannot combine non-recurring and immediate
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local options = {
                interval = 1,
                recurring = false,
                immediate = true,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "EXPIRE ", arg1, arg2, arg3)
                end,
                cancel = function(reason, arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "CANCEL ", reason, arg1, arg2, arg3)
                end,
                shm_name = "timer_shm",
                key_name = "my_key",
                sub_interval = 0.1,
            }
            local ok, err = pcall(timer.new, options, "arg1", nil, "arg3")
            if ok then
                ngx.say(true)
            else
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
the 'immediate' option requires 'recurring'



=== TEST 12: new() key_name required for sub_interval
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local options = {
                interval = 1,
                recurring = true,
                immediate = true,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "EXPIRE ", arg1, arg2, arg3)
                end,
                cancel = function(reason, arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "CANCEL ", reason, arg1, arg2, arg3)
                end,
                shm_name = "timer_shm",
                --key_name = "my_key",
                sub_interval = 0.1,
            }
            local ok, err = pcall(timer.new, options, "arg1", nil, "arg3")
            if ok then
                ngx.say(true)
            else
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
'key_name' is required when specifying 'sub_interval'



=== TEST 13: new() sub_interval >= 0
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local options = {
                interval = 1,
                recurring = true,
                immediate = true,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "EXPIRE ", arg1, arg2, arg3)
                end,
                cancel = function(reason, arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "CANCEL ", reason, arg1, arg2, arg3)
                end,
                shm_name = "timer_shm",
                key_name = "my_key",
                sub_interval = -1,
            }
            local ok, err = pcall(timer.new, options, "arg1", nil, "arg3")
            if ok then
                ngx.say(true)
            else
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
expected 'sub_interval' to be greater than or equal to 0



=== TEST 14: new() sub_interval <= interval
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local options = {
                interval = 1,
                recurring = true,
                immediate = true,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "EXPIRE ", arg1, arg2, arg3)
                end,
                cancel = function(reason, arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "CANCEL ", reason, arg1, arg2, arg3)
                end,
                shm_name = "timer_shm",
                key_name = "my_key",
                sub_interval = 2,
            }
            local ok, err = pcall(timer.new, options, "arg1", nil, "arg3")
            if ok then
                ngx.say(true)
            else
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
expected 'sub_interval' to be less than or equal to 'interval'



=== TEST 15: new() sub_interval must be a number
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local options = {
                interval = 1,
                recurring = true,
                immediate = true,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "EXPIRE ", arg1, arg2, arg3)
                end,
                cancel = function(reason, arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "CANCEL ", reason, arg1, arg2, arg3)
                end,
                shm_name = "timer_shm",
                key_name = "my_key",
                sub_interval = "hello world",
            }
            local ok, err = pcall(timer.new, options, "arg1", nil, "arg3")
            if ok then
                ngx.say(true)
            else
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
expected 'sub_interval' to be a number



=== TEST 16: new() sub_interval requires immediate
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local options = {
                interval = 1,
                recurring = true,
                immediate = false,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "EXPIRE ", arg1, arg2, arg3)
                end,
                cancel = function(reason, arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "CANCEL ", reason, arg1, arg2, arg3)
                end,
                shm_name = "timer_shm",
                key_name = "my_key",
                sub_interval = 0.1,
            }
            local ok, err = pcall(timer.new, options, "arg1", nil, "arg3")
            if ok then
                ngx.say(true)
            else
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
'immediate' is required when specifying 'sub_interval'



=== TEST 17: new() jitter must be a number
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local options = {
                interval = 1,
                jitter = "hello",
                recurring = true,
                immediate = false,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "EXPIRE ", arg1, arg2, arg3)
                end,
            }
            local ok, err = pcall(timer.new, options, "arg1", nil, "arg3")
            if ok then
                ngx.say(true)
            else
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
expected 'jitter' to be a number



=== TEST 18: new() jitter must be >= 0
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local options = {
                interval = 1,
                jitter = -1,
                recurring = true,
                immediate = false,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "EXPIRE ", arg1, arg2, arg3)
                end,
            }
            local ok, err = pcall(timer.new, options, "arg1", nil, "arg3")
            if ok then
                ngx.say(true)
            else
                ngx.log(ngx.ERR, err)
            end
        }
    }
--- request
GET /t
--- response_body

--- error_log
expected 'jitter' to be greater than or equal to 0
