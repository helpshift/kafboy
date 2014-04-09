-module(kafboy_sup).

-behaviour(supervisor).

%% API
-export([start_link/0,start_link/1,start_child/2,kill_child/1]).
%% fault-tolderance/supervisor related
-export([ get_child_spec/1 ]).
%% Supervisor callbacks
-export([init/1,restart_c/1]).

%% includes
-include("kafboy_definitions.hrl").
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% Constants
-define(SERVER, ?MODULE).
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).
-define(WORKER_PREFIX,"kafboy_").
-define(PG_PREFIX, "kafboy_pg_").
-define(RECHECK_DELAY, 10).
-define(DISABLED,false).
-define(DEBUG,false).
-define(MAX_WORKERS,2).
%% ===================================================================
%% API functions
%% ===================================================================
-spec start_link() -> {ok, pid()} | any().
start_link()->
    ?MODULE:start_link([]).

-spec start_link(State::any()) -> {ok, pid()} | any().
start_link(_Args) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, _Args).

%% get_child_spec() -> SupervisorTreeSpecifications
%% @doc The supervisor calls each worker's specification from the worker itself
%% This makes it easier to manage different workers, and placing the logic away
%% from the supervisor itself. In this case there is no need to explicitly start
%% a child worker.
get_child_spec(NoOfWorkers)->
    Workers = lists:map(fun( X )->
                WorkerId = list_to_atom(?WORKER_PREFIX++ integer_to_list(X)),
                {WorkerId, {?MODULE, start_link, [{WorkerId}] },
            permanent, 2000, worker, [?MODULE]}
    end, lists:seq(1,NoOfWorkers)),
    Workers.

%%====================================================================
%% Supervisor callbacks
%%====================================================================
%%--------------------------------------------------------------------
%% Func: init(Args) -> {ok,  {SupFlags,  [ChildSpec]}} |
%%                     ignore                          |
%%                     {error, Reason}
%% Description: Whenever a supervisor is started using
%% supervisor:start_link/[2,3], this function is called by the new process
%% to find out about restart strategy, maximum restart frequency and child
%% specifications.
%%--------------------------------------------------------------------
%% @private
-spec init(list()) -> {ok, _}.
init(InitArgs) ->
    Workers = case InitArgs of
          _ ->
              lists:flatten (
                kafboy_startup_worker:get_child_spec(1)
                %++ kafboy_mgr_db:get_child_spec(1)
                %++ kafboy_proxy:get_child_spec(1)
                %++ kafboy_http_api:get_child_spec(1)
               )
          end,

    {ok, {{ one_for_one, 10, 10},
      Workers }
    }.

%%====================================================================
%% Internal functions
%%====================================================================
start_child(Module,ChildSpec) when is_tuple(ChildSpec) ->
    supervisor:start_child(Module,ChildSpec);

start_child(Module,InitArgs) ->
    case Module:get_child_spec(InitArgs) of
        [] ->
            ?INFO_MSG("not starting ~p since []",[InitArgs]),
            ok;
        [ChildSpec] ->
            start_child(Module,ChildSpec);
        _E ->
            error_logger:info_msg("~n ~p unexp when start_child. got ~p",[Module,_E]),
            error
    end.

kill_child(SID) ->
    GroupName = "kafboy_worker_"++SID,
    PID = pg2:get_closest_pid(GroupName),
    {ok, {_,ChildSpecs}} = ?MODULE:init(SID),
    [ supervisor:terminate_child(PID,ChildSpec) || ChildSpec <- ChildSpecs].

restart_c(SID) ->
    GroupName = "kafboy_worker_"++SID,
    PID = pg2:get_closest_pid(GroupName),
    {ok, {_,ChildSpecs}} = ?MODULE:init(SID),
    [ supervisor:restart_child(PID,ChildSpec) || ChildSpec <- ChildSpecs].
