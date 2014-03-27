-record(kafboy_startup,{
      logging,profiling
}).

-record(kafboy_enabled, {
      modules,functions,pids,times,levels
}).

-record(kafboy_route,{
      id,node,pid,props={v1,[]}
}).

-record(kafboy_lastids,{
      table,
      lastid
}).
