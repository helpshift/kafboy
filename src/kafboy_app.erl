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

    case application:get_env(ekaf, ekaf_bootstrap_broker) of
        undefined ->
            io:format("~n %% KAFBOY WARNING",[]),
            io:format("~n %% Please add an app env for the ekaf_bootstrap_broker",[]),
            io:format("~n %% {ekaf, [ {ekaf_bootstrap_broker, {\"localhost\", 9091}} ]",[]),
            io:format("~n %%",[]),
            {stop,{missing,ekaf_bootstrap_broker}};
        _ ->
            start_with_ekaf(_StartType, _StartArgs)
    end.

get_config_urls(#kafboy_http{ sync = false, batch = true } = State)->
    [ {Url, kafboy_http_handler, State } || Url <- get_default(kafboy_routes_async_batch, [])];
get_config_urls(#kafboy_http{ sync = true } = State) ->
    [ {Url, kafboy_http_handler, State } || Url <- get_default(kafboy_routes_sync, [])];
get_config_urls(#kafboy_http{ sync = false } = State) ->
    [ {Url, kafboy_http_handler, State } || Url <- get_default(kafboy_routes_async, [])].

get_routes(InitState)->
    [InitState#kafboy_http{ sync=false, batch=true},
     InitState#kafboy_http{ sync=true },
     InitState#kafboy_http{ sync=false }].

start_with_ekaf(_StartType, _StartArgs)->
    SyncUrl = get_default(kafboy_sync_url,?KAFBOY_DEFAULT_SYNC_URL),
    AsyncUrl = get_default(kafboy_async_url,?KAFBOY_DEFAULT_ASYNC_URL),
    Port = get_default(kafboy_http_port,?KAFBOY_DEFAULT_HTTP_PORT),
    EditJsonCallback = get_default(kafboy_callback_edit_json, undefined),
    InitState = #kafboy_http{ callback_edit_json  = EditJsonCallback},
    CustomUrls = lists:foldl(fun(TempState,Acc)->
                                     get_config_urls(TempState) ++ Acc
                             end,[], get_routes(InitState)),
    Dispatch = cowboy_router:compile([{'_',
                                       CustomUrls ++
                                       [{"/echo_post", kafboy_disco_handler,InitState},
                                        {"/disco",     kafboy_disco_handler,InitState},

                                        {SyncUrl,  kafboy_http_handler, InitState},
                                        {AsyncUrl, kafboy_http_handler, InitState#kafboy_http{ sync = false}},

                                        {"/batch/"++SyncUrl,  kafboy_http_handler, InitState#kafboy_http{ batch=true}},
                                        {"/batch/"++AsyncUrl, kafboy_http_handler, InitState#kafboy_http{ sync=false, batch=true}}
                                       ]}
                                     ]),
    %?INFO_MSG("start with port ~p syncurl ~p asyncurl ~p",[Port,SyncUrl,AsyncUrl]),
    {ok, _Ref} = cowboy:start_http(http, 100, [{port, Port}], [
                                                              {env, [{dispatch, Dispatch}]}
                                                              ,{backlog, 128}
                                                              ,{max_connections, 10000}
                                                              %,{max_keepalive, 150}
                                                              %,{timeout,100}
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

get_default(Key,Default)->
    case kafboy_startup_worker:read_env(Key) of
        {true,Val}->
            Val;
        _ ->
            Default
    end.
