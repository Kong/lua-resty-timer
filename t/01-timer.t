use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

workers(1);

plan tests => repeat_each() * (blocks() * 3) - 4;

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_shared_dict test_shm 8m;
    lua_shared_dict timer_shm 8m;
};

run_tests();

__DATA__

=== TEST 1: new() timer runs periodically
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
                cancel = function(premature, arg1, arg2, arg3)
                    ngx.log(ngx.ERR, "CANCEL ", premature, arg1, arg2, arg3)
                end,
                --shm_name = "timer_shm",
                --key_name = "my_key",
            }
            local t = timer(options, "arg1", nil, "arg3")
            ngx.sleep(0.55)  -- 5 occurences
            t:cancel()
            ngx.say(true)
        }
    }
--- request
GET /t
--- response_body
true
--- grep_error_log eval: qr/EXPIRE arg1nilarg3|CANCEL nilarg1nilarg3/
--- grep_error_log_out eval
qr/^EXPIRE arg1nilarg3
EXPIRE arg1nilarg3
EXPIRE arg1nilarg3
EXPIRE arg1nilarg3
EXPIRE arg1nilarg3
CANCEL nilarg1nilarg3$/



=== TEST 2: new() timer runs once if not recurring
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local count = 0
            local options = {
                interval = 0.1,
                recurring = false,
                immediate = false,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    count = count + 1
                end,
                --shm_name = "timer_shm",
                --key_name = "my_key",
            }
            local t = timer(options, "arg1", nil, "arg3")
            ngx.sleep(0.55)  -- could be 5 occurences
            ngx.say(count)
        }
    }
--- request
GET /t
--- response_body
1



=== TEST 3: new() only a single timer runs per shm key
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local count = 0
            local options = {
                interval = 0.1,
                recurring = true,
                immediate = false,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    count = count + 1
                end,
                shm_name = "timer_shm",
                key_name = "my_key",
            }
            for x = 1,10 do
                -- create 10 timers with same shm key
                -- only 1 should run
                timer(options, "arg1", nil, "arg3")
            end
            ngx.sleep(0.55)  -- could be 10 x 5 = 50 occurences
            ngx.say(count)
        }
    }
--- request
GET /t
--- response_body
5



=== TEST 4: new() timer runs immediately
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local count = 0
            local options = {
                interval = 0.1,
                recurring = true,
                immediate = true,
                detached = false,
                expire = function(arg1, arg2, arg3)
                    count = count + 1
                end,
                --shm_name = "timer_shm",
                --key_name = "my_key",
            }
            local t = timer(options, "arg1", nil, "arg3")
            ngx.sleep(0.15)  -- could be 1 occurence, +1 for immediate
            ngx.say(count)
        }
    }
--- request
GET /t
--- response_body
2



=== TEST 5: new() sub_interval is honored
--- http_config eval: $::HttpConfig
--- config
    location = /t {
        content_by_lua_block {
            local timer = require("resty.timer")
            local count = 0
            local t = {}
            ngx.update_time()
            local t0 = ngx.now()
            local options = {
                interval = 0.1,
                recurring = true,
                immediate = true,
                detached = false,
                expire = function(t_id)
                    count = count + 1
                    ngx.update_time()
                    --print("========EXEC=======> ", t_id, " @ ", 1000*(ngx.now() - t0))
                    if t_id == 1 then
                        t[t_id]:cancel() -- cancel so it ran only once
                    end
                end,
                shm_name = "timer_shm",
                key_name = "my_key",
                sub_interval = 0.01,
            }
            for x = 1,2 do
                -- create 2 timers with same shm key
                -- only 1 should run
                t[x] = timer(options, x)
                ngx.update_time()
                --print("=======SCHED=======> ",x, " @ ", 1000*(ngx.now() - t0))
                -- wait till half way interval before scheduling the second one
                ngx.sleep(options.interval / 2)
            end
            -- first timer ran on start, so count == 1, timer 1 was immediately cancelled
            ngx.sleep(options.interval / 2) -- lock set by 1st timer expires, the first half was already done when creating the timers above
            ngx.sleep(options.sub_interval * 1.5) -- by now the second timer should have taken over (count == 2)
            ngx.say(count) --> 2; first when first timer starts, 2nd by second timer after it picked up
        }
    }
--- request
GET /t
--- response_body
2
