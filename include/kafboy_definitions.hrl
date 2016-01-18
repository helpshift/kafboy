%%======================================================================
%% Defaults
%%======================================================================
-define(KAFBOY_DEFAULT_SYNC_URL        , "/sync/:topic/").
-define(KAFBOY_DEFAULT_ASYNC_URL       , "/async/:topic/").
-define(KAFBOY_DEFAULT_HTTP_PORT       , 8000).

-include_lib("ekaf/include/ekaf_definitions.hrl").

%%======================================================================
%% Macros
%%======================================================================
-define(KAFBOY_AUTOSTART, true).
-define(TCP_DEFAULT_SEND_OPTIONS,[{active, once},{nodelay,true},{keepalive,true},{broadcast,false}]).

%%======================================================================
%% Records
%%======================================================================
%% available to every request
-record(kafboy_http, { sync=false::boolean(),
                       batch=false::boolean(),
                       callback_edit_json}).

-record(kafboy_startup,{
      logging,
      profiling
}).

-record(kafboy_enabled, {
      modules,
      functions,
      pids,
      times,
      levels
}).
