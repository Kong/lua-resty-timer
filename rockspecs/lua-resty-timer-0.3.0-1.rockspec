package = "lua-resty-timer"
version = "0.3.0-1"
source = {
   url = "https://github.com/kong/lua-resty-timer/archive/0.3.0.tar.gz",
   dir = "lua-resty-timer-0.3.0"
}
description = {
   summary = "Extended timer library for OpenResty",
   detailed = [[
      Provided recurring, cancellable, node-wide timers, beyond what the
      basic OR timers do.
   ]],
   license = "Apache 2.0",
   homepage = "https://github.com/kong/lua-resty-timer"
}
dependencies = {
}
build = {
   type = "builtin",
   modules = {
     ["resty.timer"] = "lib/resty/timer.lua",
   }
}
