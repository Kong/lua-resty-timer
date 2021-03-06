package = "lua-resty-timer"
version = "scm-1"
source = {
   url = "git://github.com/kong/lua-resty-timer",
   branch = "master"
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
