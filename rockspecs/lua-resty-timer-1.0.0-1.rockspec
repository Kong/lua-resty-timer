package = "lua-resty-timer"
version = "1.0.0-1"
source = {
   url = "git://github.com/kong/lua-resty-timer",
   tag = "1.0.0"
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
