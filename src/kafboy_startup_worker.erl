-module(kafboy_startup_worker).

-behaviour(gen_server).

%% API
-export([
         get_child_spec/0, get_child_spec/1, read_env/1,
         cookie_setup/0,
         kickoff/1,
         kickoff_master/1,kickoff_master_new_node/1,kickoff_master_restart/1,
         kickoff_slave/1,
         slave_added/1,
         setup_metrics/0, later/0, bootup/0,
         log/4, info/0, profile_modules/1, get_bin_path/0
    ]).
%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------
-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% includes
-include("kafboy_definitions.hrl").
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.


%% Constants
-define(SERVER, ?MODULE).
-define(WORKER_PREFIX,"kafboy_startup_").
-define(DISABLED,false).
-define(DEBUG,false).
-define(MAX_WORKERS,1).

%%%===================================================================
%%% API
%%%===================================================================
log(Mod,Line,Format, Args)->
    gen_server:cast(?SERVER,{log,Mod,Line,Format,Args}).

info()->
    gen_server:call(?SERVER,info).

profile_modules(_Args)->
    application:start(runtime_tools),

    case ?MODULE:read_env(kafboy_profiling_apps) of
        {ProfilingApps,true} ->
            [ application:start(ProfilingApp) || ProfilingApp <- ProfilingApps ];
        _E ->
            ok
    end,

    %application:start(statsderl),

    ?MODULE:setup_metrics(),

    case ?MODULE:read_env(kafboy_enable_trace) of
    {_,true} ->
        kafboy_logger:enable_trace(),
        lists:foldl(fun(ModToAdd,Acc)->
                [
                 dbg:tpl({ModToAdd,FuncToAdd,'_'},[])
                 || FuncToAdd <- kafboy_logger:enabled_functions()
                ],

                sets:add_element(ModToAdd,Acc)
            end, sets:new(), kafboy_logger:enabled_modules() );
    _ ->
        sets:new()
    end.

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Args) ->
     gen_server:start_link({local,?SERVER}, ?MODULE, Args,[]).

%% get_child_spec() -> SupervisorTreeSpecifications
%% @doc The supervisor calls each worker's specification from the worker itself
%% This makes it easier to manage different workers, and placing the logic away
%% from the supervisor itself. In this case there is no need to explicitly start
%% a child worker.
get_child_spec()->
    ?MODULE:get_child_spec(?MAX_WORKERS).

get_child_spec(_NoOfWorkers)->
    Worker = {kafboy_startup_worker, {kafboy_startup_worker, start_link, [[read_env(trace),read_env(debug), read_env(fresh)]] }, temporary, 2000, worker, dynamic},
    [Worker].

read_env(Field) ->
    Got = application:get_env(kafboy,Field),
    case Got of
        {ok,Val} ->
            {true,Val};
            _E ->
                {false,Field}
    end.

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------
init(Args) ->
    %% Note: don't call ?INFO_MSG until here
    Set = ?MODULE:profile_modules(Args),

    %% your {kafboy,[]} app config can decide whether to trace calls
    State =  #kafboy_startup{logging=#kafboy_enabled{modules=Set}},

    ?MODULE:kickoff(Args),

    {ok, State}.

kickoff(Args)->

    %% deps
    %%A = sha2:start(),
    A = ok,

    %% security
    B = ?MODULE:cookie_setup(),

    %% master vs slave
    C = case ?MODULE:read_env(kafboy_master) of
            {_,true} ->
                kickoff_master(Args);
            _ ->
                kickoff_slave(Args)
        end,

    {ok,[
     {sha,A},
     {cookie,B},
     {kickoff,C}
    ]}.

kickoff_master(Args)->
    %% Boilerplate for future distributed work.
    %% For now just joins cluster
    case ?MODULE:read_env(kafboy_fresh) of
        {_,true} ->
            ?INFO_MSG("asked to kickoff new node since value of new in ~p",[Args]),
            ?MODULE:kickoff_master_new_node(Args),
            ok;
        NotTrue->
            ?INFO_MSG("asked to kickoff restart since value of new in ~p is ~p, ~nknown nodes are ~p",[Args,NotTrue,nodes()]),
            ?MODULE:kickoff_master_restart(Args),
            ok
    end,

    later_master().

kickoff_master_new_node(_Args)->
    ?INFO_MSG("done kickoff new node",[]),
    ok.

kickoff_master_restart(_Args)->
    ?INFO_MSG("going to call kafboy_mgr_db:init/0",[]),
    ok.

kickoff_slave(_Args)->
    %% ask master to allow location transparent access
    %%  of tables to this node
    case ?MODULE:read_env(kafboy_load_balancer) of
        {DiscoUrl,true} ->
            case httpc:request(get, {DiscoUrl, []}, [
                                                     %% TODO: ssl support ?
                                                     %% {ssl,[{verify,verify_peer}]}
                                                    ], [{sync, true}]) of
                {ok,{_Status, _Headers, Result}} ->
                    MasterNode = list_to_atom(Result),
                    ping_master(MasterNode),
                    ok;
                _E ->
                    ?INFO_MSG("Cant ping master since didnt get expected node as result for /disco => ~n~p",[_E])
            end;

        _ ->
            ok
    end,
    later_slave().

ping_master(MasterNode)->
    SelfNode = node(),

    A = net_adm:ping(MasterNode),

    ?INFO_MSG("Slave ~p pinging master ~p gave ~p",[SelfNode,MasterNode,A]),

    A.


slave_added(_SlaveNode)->
    ok.

cookie_setup()->
    case ?MODULE:read_env(kafboy_set_cookie) of
        {CookieVal,true} ->
            erlang:set_cookie(node(),CookieVal);
        _ ->
            ok
    end.

handle_call({log,enable_module,Mod},_From, State) ->
    PresentSet = (State#kafboy_startup.logging)#kafboy_enabled.modules,
    NextSet = sets:add_element(Mod,PresentSet),
    NextLogging = #kafboy_enabled{modules=NextSet},
    dbg:tpl({Mod,'_','_'},[]),
    NextState = State#kafboy_startup{logging=NextLogging},
    {reply, ok, NextState};

handle_call({log,disable_module,Mod},_From, State)->
    PresentSet = (State#kafboy_startup.logging)#kafboy_enabled.modules,
    NextSet = sets:del_element(Mod,PresentSet),
    dbg:ctpl(Mod,'_','_'),
    NextLogging = #kafboy_enabled{modules=NextSet},
    NextState = State#kafboy_startup{logging=NextLogging},
    {reply, ok, NextState};

handle_call({trace_enable_module,_Mod},_From, State)->
    {reply, false, State};

handle_call(_Msg,_From, State)->
    io:format("~p:handle_info/3 unknown guard for ~p",[?MODULE,_Msg]),
    {reply, State, State}.

%% Cast
handle_cast({log,Mod,Line,Format,Args}=_Msg,State)->
    %%io:format("~p:handle_cast/2 log ~p",[?MODULE,_Msg]),
    Mods = (State#kafboy_startup.logging)#kafboy_enabled.modules, %%kafboy_logger:enabled_modules()
    case  sets:is_element(Mod,Mods) of
       true ->
        kafboy_logger:info_msg(Mod,Line,Format, Args);
    _ ->
        ok
    end,
    {noreply,State};

handle_cast(_Msg, State) ->
    io:format("~p:handle_cast/2 unknown guard for ~p",[?MODULE,_Msg]),
    {noreply, State}.

handle_info(_Info, State) ->
    io:format("~p:handle_info/2 unknown guard for ~p",[?MODULE,_Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

get_bin_path() ->
    case os:getenv("BIN_PATH") of
        false ->
            case code:priv_dir(kafboy) of
                {error, _} ->
                    ".";
                Path ->
            filename:join([Path, "bin"])
            end;
        Path ->
            Path
    end.

later()->
    case ?KAFBOY_AUTOSTART of
        true ->
            spawn(fun()->
                          receive _X -> ok
                          after 5000 ->
                                  ?MODULE:bootup()
                          end
                  end);
    _ ->
            ?INFO_MSG("not auto-starting previously started acccounts",[])
    end.

later_master()->
    later(),
    ok.

later_slave()->
    later(),
    ok.

bootup()->
    ok.

setup_metrics()->
    Metrics = metrics(),

    lists:map(fun(X) when is_binary(X) ->
              %folsom_metrics:new_histogram(<<"slide.",X/binary>>,slide_uniform, {60,1028}),
              %folsom_metrics:new_counter(<<"counter.",X/binary>>);(X) ->
              ok;
         (X)->
              ?INFO_MSG("dont know what to do with ~p",[X])
          end, Metrics).

metrics()->
    [].
