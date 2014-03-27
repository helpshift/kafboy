-module(kafboy_startup_worker).

-behaviour(gen_server).

%% API
-export([log/4, info/0, profile_modules/1, read_env/1]).
-export([get_bin_path/0, get_pid_file/0, load_drivers/1,

     set_cookie/1, initSpawns/0,wait_for_tables/1,wait_for_tables_done/1,

     kickoff/1,
     kickoff_master/1,kickoff_master_new_node/1,kickoff_master_restart/1,
     kickoff_slave/1,

     slave_added/1,

     setup_metrics/0, later/0
    ]).
%% includes
-include("kafboy_definitions.hrl").
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-define(MNESIA_WAIT_TABLES,[kafboy_route]).
-define(MNESIA_WAIT_TIMEOUT,500000).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------
-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).
-export([ get_child_spec/1 ]).

%% Constants
-define(SERVER, ?MODULE).
-define(WORKER_PREFIX,"kafboy_startup_").
-define(PG_PREFIX, "it_startup_pg_").
-define(RECHECK_STRATEGY,recheck).
-define(RECHECK_DELAY, 10).
-define(DISABLED,false).
-define(DEBUG,false).
-define(MAX_WORKERS,1).
-record(state, {ctr=0}).

%%%===================================================================
%%% API
%%%===================================================================
log(Mod,Line,Format, Args)->
    gen_server:cast(?SERVER,{log,Mod,Line,Format,Args}).

info()->
    gen_server:call(?SERVER,info).

profile_modules(Args)->
    application:start(runtime_tools),

    case ?MODULE:read_env(kafboy_profiling_apps) of
        {ProfilingApps,true} ->
            [ application:start(ProfilingApp) || ProfilingApp <- ProfilingApps ];
        _E ->
            ?INFO_MSG("ignore ~p",[_E]),
            ok
    end,

    %application:start(statsderl),

    ?MODULE:setup_metrics(),

    case ?MODULE:read_env(kafboy_enable_trace) of
    {_,true} ->
        dbg:start(),
        dbg:tracer(),
        dbg:p(all,[c]),
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

get_child_spec(NoOfWorkers)->
    XWorkers = lists:map(fun( X )->
                WorkerId = list_to_atom(?WORKER_PREFIX++ integer_to_list(X)),
                {WorkerId, {?MODULE, start_link, [{WorkerId}] },
            permanent, 2000, worker, [?MODULE]}
    end, lists:seq(1,NoOfWorkers)),
    Worker = {kafboy_startup_worker, {kafboy_startup_worker, start_link, [[read_env(trace),read_env(debug), read_env(fresh)]] }, temporary, 2000, worker, dynamic},
    %Eredis = {eredis, {eredis, start, [eredisclient]}, temporary, 2000, worker, dynamic},
    Workers = [
           Worker
           %,Eredis
          ],
    Workers.

read_env(Field) ->
    Got = application:get_env(kafboy,Field),
    R = case Got of
        {ok,_R} ->
        _R;
        _E ->
        false
    end,
    %?INFO_MSG("application:get_env(kafboy,~p) => ~p read_env=> {~p,~p}",[Field,Got,Field,R]),
    {Field,R}.

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------
init(Args) ->
    %% Note: don't call ?INFO_MSG until here
    io:format("~n init ~p with ~p",[?MODULE,Args]),
    Set = profile_modules(Args),
    State =  #kafboy_startup{logging=#kafboy_enabled{modules=Set}},
    %Kickoff = ?MODULE:kickoff(Args),
    {ok, State}.

kickoff(Args)->

    %% deps
    A = sha:start(),

    %% security
    B = ?MODULE:set_cookie(Args),
    ?INFO_MSG("set cookie, now kickoff based on ~p",[application:get_env(kafboy,master)]),

    %% master vs slave
    C = case ?MODULE:read_env(kafboy_master) of
            {_,true} ->
                ?INFO_MSG("start master",[]),
                kickoff_master(Args);
            _ ->
                ?INFO_MSG("start slave",[]),
                kickoff_slave(Args)
        end,


    %% starting registered process alias's
    D = ?MODULE:initSpawns(),

    {ok,[
     {sha,A},
     {cookie,B},
     {kickoff,C},
     {spawns,D}
    ]}.

kickoff_master(Args)->
    %% db
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

    ?INFO_MSG("begin waiting for tables...",[]),
    case catch ?MODULE:wait_for_tables(?MNESIA_WAIT_TIMEOUT) of
    {'EXIT',_Er}->
        io:format("back in wait table donem with error ~p",[_Er]);

    Apps ->
        io:format("~n back in wait tables done with ~p",[Apps])
    end,

    later_master().

kickoff_master_new_node(Args)->
    %% init db
    % kafboy_mgr_db:new(),
    ?INFO_MSG("done kickoff new node",[]),
    ok.

kickoff_master_restart(Args)->

    ?INFO_MSG("going to call kafboy_mgr_db:init/0",[]),

    %% start db
    %A = kafboy_mgr_db:start().

    ok.

kickoff_slave(Args)->
    %% ask master to allow location transparent access
    %%  of tables to this node
    DiscoUrl = case ?MODULE:read_env(kaboy_is_master) of
           {_,true} ->
               "http://TODO:5282/disco";
           _ ->
               "http://localhost:5282/disco"
           end,
    ?INFO_MSG("Going to contact master by pinging ~p",[DiscoUrl]),

    case httpc:request(get, {DiscoUrl, []}, [
                        %{ssl,[{verify,verify_peer}]}
                        ], [{sync, true}]) of
    {ok,{_Status, _Headers, Result}} ->
        MasterNode = list_to_atom(Result),
        ping_master(MasterNode),
        ok;
    _E ->
        ?INFO_MSG("Cant ping master since didnt get expected node as result for /disco => ~n~p",[_E])
    end.

ping_master(MasterNode)->
    SelfNode = node(),

    A = net_adm:ping(MasterNode),

    ?INFO_MSG("Slave pinging master ~p gave ~p, starting mnesia",[MasterNode,A]),

    mnesia:start(),

    B = rpc:call(MasterNode, ?MODULE, slave_added, [SelfNode]),
    ?DEBUG_MSG("Slave rpc master ~p gave ~p",[B]),

    C = later_slave(),

    {MasterNode,[A,B,C]}.


slave_added(SlaveNode)->
    R =  mnesia:change_config(extra_db_nodes,nodes()),
    ?INFO_MSG("adding location transparency ~p, nodes is ~p",
          [R,nodes()]),
    R.

set_cookie(Args)->
    FinalCookieVal = case ?MODULE:read_env(kafboy_cookie) of
              {_,CookieVal} ->
                 CookieVal;
             _ ->
                 ?INFO_MSG("expected cookie in vars. using default instead",[]),
                 ?KAFBOY_DEFAULT_COOKIE_ERLANG
             end,
    ?INFO_MSG("setting cookie to node '~p' as '~p'",[node(),FinalCookieVal]),
    erlang:set_cookie(node(),FinalCookieVal).

initSpawns()->
    %% starting mnesia related registed process alias's
    % _A = kafboy_mgr_db:initSpawns(),

    ok.

wait_for_tables(Started)->
    case mnesia:wait_for_tables(?MNESIA_WAIT_TABLES,?MNESIA_WAIT_TIMEOUT) of
        ok->
            ?MODULE:wait_for_tables_done("within "++ integer_to_list(Started));
        _E1  ->
            Rem = Started rem (?MNESIA_WAIT_TIMEOUT * 300) ,
            case Rem of
                0 ->
                    io:format("still waiting after 10 attempts",[]),
                    timer:apply_after(?MNESIA_WAIT_TIMEOUT, ?MODULE, wait_for_tables, [Started+?MNESIA_WAIT_TIMEOUT]),
                    ok;
                _E2 ->
                    io:format("~nnope,still wait...~p",[_E2]),
                    timer:apply_after( ?MNESIA_WAIT_TIMEOUT, ?MODULE, wait_for_tables, [Started+?MNESIA_WAIT_TIMEOUT] ),
                    ok
            end
    end.

wait_for_tables_done(Msg)->


    %% anything that needs mnesia to function, can be called here
    ToRun = [
              %some app:start()
            ],

    %some callback

    ToRun.


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

handle_call({trace_enable_module,Mod},_From, State)->
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

load_drivers(_)->
    ok.

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

%% @spec () -> false | string()
get_pid_file() ->
    case os:getenv("PID_PATH") of
    false ->
        false;
    "" ->
        false;
    Path ->
        Path
    end.


later()->
    case ?KAFBOY_AUTOSTART of
        true ->
            spawn(fun()->
                          receive X -> ok
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
    exometer:new([erlang,memory], {function,erlang,memory,['$dp'], value,
                                   [total,processes,ets,binary,atom,
                                    atom_used,maximum]}),

    exometer:new([erlang, statistics], {function, erlang, statistics, ['$dp'], value,
                                        [run_queue]}),

    exometer:new([erlang, system_info], {function, erlang, system_info, ['$dp'], value,
                                         [logical_processors, logical_processors_available, logical_processors_online,
                                          port_count, port_limit, process_count, process_limit, thread_pool_size]}),

    StatsSrv = {stress_exometer_srv,
                {stress_exometer_srv, start_link, []},
                permanent,
                5000,
                worker,
                []},
    [

     % ?KAFBOY_EVENT_DB_ERROR_BIN,
     % ?KAFBOY_EVENT_DB_TIMEOUT_BIN,

     % ?KAFBOY_EVENT_CACHE_HIT_BIN,
     % ?KAFBOY_EVENT_CACHE_MISS_BIN,

     % ?KAFBOY_EVENT_ROUTING_BIN,
     % ?KAFBOY_EVENT_ROUTING_OK_BIN,
     % ?KAFBOY_EVENT_ROUTING_FAILED_BIN

    ].
