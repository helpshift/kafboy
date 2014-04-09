%%======================================================================
%% Defaults
%%======================================================================
-define(KAFBOY_DEFAULT_SYNC_URL        , "/sync/:topic/").
-define(KAFBOY_DEFAULT_ASYNC_URL       , "/async/:topic/").
-define(KAFBOY_DEFAULT_HTTP_PORT       , 8000).
%%======================================================================
%% Debugging Toggles
%%======================================================================
-define(KAFBOY_VERSION                 , 0.1).


%%======================================================================
%% Macros
%%======================================================================
-include("kafboy_records.hrl").
%%======================================================================
%% Database

%%======================================================================
%% Security
%%======================================================================
-define(KAFBOY_DEFAULT_COOKIE_ERLANG,<<"afkak">>).
%-include("kafboy_creds.hrl").
-include_lib("ekaf/include/ekaf_definitions.hrl").
%%======================================================================
%% Configs
%%======================================================================
-define(KAFBOY_AUTOSTART, true).
-define(TCP_DEFAULT_SEND_OPTIONS,[{active, once},{nodelay,true},{keepalive,true},{broadcast,false}]).
%%======================================================================
%% set/get Keys
%%======================================================================
-define(KAFKA_STATSS_NS      , <<"kafboy">>).

%%======================================================================
%% Records
%%======================================================================
%%-include("kaboy_literals.hrl").
-record(kafboy_http, { ctr = 0::integer(), sync=false::boolean(), batch=false::boolean(), safe=false::boolean(), error, callback_edit_json, callback_auth}).
