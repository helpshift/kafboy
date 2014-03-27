-module(kafboy_app).

-behaviour(application).

%% Application callbacks
-export([start/1, start/2, stop/1]).

%% includes
-include("kafboy_definitions.hrl").
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-define(setup(F), {setup, fun start/0, fun stop/1, F}).

%% ===================================================================
%% Application callbacks
%% ===================================================================
%% @private
-spec start(normal | {takeover, node()} | {failover, node()},
            any()) -> {ok, pid()} | {ok, pid()} |
                      {error, Reason::any()}.
start(_StartType)->
    ?MODULE:start(_StartType,[]).

start(_StartType, _StartArgs) ->


    SyncUrl = case kafboy_startup_worker:read_env(sync_url) of
                  {Url1,true}->
                      Url1;
                  _ ->
                      ?KAFBOY_DEFAULT_SYNC_URL
              end,
    AsyncUrl = case kafboy_startup_worker:read_env(async_url) of
                  {Url2,true}->
                      Url2;
                  _ ->
                      ?KAFBOY_DEFAULT_ASYNC_URL
              end,

    Dispatch = cowboy_router:compile([
                                      {'_', [
                                             {SyncUrl, kafboy_http_handler, [{sync,true}]},
                                             {AsyncUrl, kafboy_http_handler, [{sync,false}]}
                                            ]}
                                     ]),
    {ok, _} = cowboy:start_http(http, 100, [{port, 8000}], [
                                                            {env, [{dispatch, Dispatch}]}
                                                           ]),
    case kafboy_sup:start_link(_StartArgs) of
    {ok,Pid}->
        {ok,Pid};
    _Error ->
        {stop,_Error}
    end.

-spec stop(State::any()) -> ok.
stop(_State) ->
    ok.

%% ===================================================================
%% Tests
%% ===================================================================
%% -ifdef(TEST).
%% simple_test() ->
%%     ok = application:start(kafboy),
%%     io:format("this is a simple test"),
%%     ?debugMsg("Function simple_test starting..."),
%%     ?assertNot(undefined == whereis(kafbo_sup)).
%%-endif.
