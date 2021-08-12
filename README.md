# lua-resty-timer

[![Build Status][badge-travis-image]][badge-travis-url]

Extended timers for OpenResty. Provided recurring, cancellable, node-wide timers,
beyond what the basic OpenResty timers do.

## Status

This library is production ready.

## Synopsis

```nginx
http {
    lua_shared_dict timer_shm 1m;
    init_worker_by_lua_block {
        local timer = require("resty.timer")

        local options = {
            interval = 0.1,           -- expiry interval in seconds
            recurring = true,         -- recurring or single timer
            immediate = true,         -- initial interval will be 0
            detached = false,         -- run detached, or be garbagecollectible
            jitter = 0.1,             -- add a random interval
            expire = object.handler,  -- callback on timer expiry
            cancel = function(reason, self, param1)
                -- will be called when the timer gets cancelled
            end,
            shm_name = "timer_shm",   -- shm to use for node-wide timers
            key_name = "my_key",      -- key-name to use for node-wide timers
            sub_interval = 0.1,       -- max cross worker extra delay
            max_use = 1000,           -- maximum re-use of timer context
        }

        local object
        object = {                            -- create some object with a timer
            count = 0,
            handler = function(self, param1)  -- the timer callback as a method
                -- do something here
                print(param1)                 --> "Param 1"
            end,

            -- create and add to object, but also pass it as 'self' to the handler
            timer = timer(options, object, "Param 1"),
        }

        -- anchor the object and timer
        _M.global_object = object     -- will be collected if not anchored

        -- cancel the timer
        object.timer:cancel()
    }
}
```

## Description

The OpenResty timer is fairly limited, this timer adds a number of common
options as parameters without having to recode (and retest) them in each
project.

* recurring timers (supported by OR as well through `ngx.timer.every`, but this
  implementation will not run overlapping timers)

* immediate first run for recurring timers

* cancellable timers

* cancel callback, called when the timer is cancelled

* garbage collectible timers, enabling timers to (optionally) be attached to
  objects and automatically stop when garbage collected.

* node-wide timers: the same timer started in each worker will still only
  run once across the system. If the worker running it is removed the
  timer will automatically be executed on another worker.

See the [online LDoc documentation](https://kong.github.io/lua-resty-timer/topics/README.md.html)
for the complete API.

## Performance and optimizations

This timer implementation is based on "sleeping on a timer-context". This means
that a single timer is created, and in between recurring invocations `ngx.sleep`
is called as a delay to the next invocation. This as opposed to creating a new
Nginx timer for each invocation. This is configurable however.

Creating a new context is a rather expensive operation. Hence we keep the context
alive and just sleep without the need to recreate it. The downside is that there
is the possibility of a memory leak. Since a timer is implemented in OR as a
request and requests are short-lived, some memory is not released until after the
context is destroyed.

The setting `max_use` controls the timer behaviour. The default value is `1000`,
which means that after each `1000` invocations the timer context is destroyed
and a new one is generated (this happens transparent to the user).

Optimizing this setting (very opinionated/arbitrary!):

 * if the timer interval is more than `60` seconds, then keeping the context
   around in idle state for that period is probably more expensive resource wise
   than having to recreate the context. So use `max_use == 1` to drop the
   context after each invocation.

 * if the timer interval is less than `5` seconds then reusing the context makes
   sense. Assume recycling to be done once per minute, or for very high
   frequency timers (and hence higher risk of memory leak), more than once per
   minute.

## History

Versioning is strictly based on [Semantic Versioning](https://semver.org/)

### Releasing new versions:

* update changelog below (PR's should be merged including a changelog entry)
* based on changelog determine new SemVer version
* create a new rockspec
* render the docs using `ldoc` (don't do this within PR's)
* commit as "release x.x.x" (do not include rockspec revision)
* tag the commit with "x.x.x" (do not include rockspec revision)
* push commit and tag
* upload rock to luarocks: `luarocks upload rockspecs/[name] --api-key=abc`

### unreleased

  * Feat: provide a stacktrace upon errors in the timer callback
  * Feat: add a `max_use` option. This ensures timer-contexts are recycled to
    prevent memory leaks.
  * Feat: adds a new function `sleep` similar to `ngx.sleep` except that it is
    interrupted on worker exit.
  * Fix: now accounts for execution time of the handler, when rescheduling.

### 1.1.0 (6-Nov-2020)

  * Feat: add a `jitter` option. This adds a random interval to distribute the
  timers (in case of scheduling many timers at once).

### 1.0.0 (21-Sep-2020)

  * Change [BREAKING]: the recurring timers are now implemented as a sleeping
  thread which is more efficient. Side effect is that the timer only gets
  rescheduled AFTER executing the handler. So if the handler is long running,
  then individual runs will be further apart.

### 0.3 (28-May-2018)

  * Feat: added cancellation callback invocation on timer being GC'ed. This
  changes the first argument of the `cancel` callback, and hence is
  breaking.

### 0.2 (12-Feb-2018) Bug fix

  * Fix: bugfix in `unpack` function not honoring table length parameter
  * Docs: small fixes and typo's

### 0.1 (22-Nov-2017) Initial release

  * Added `sub_interval` option to reduce delays
  * Initial upload

## Copyright and License

```
Copyright 2017 - 2018 Kong Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

[badge-travis-url]: https://travis-ci.com/Kong/lua-resty-timer/branches
[badge-travis-image]: https://travis-ci.com/Kong/lua-resty-timer.svg?branch=master
