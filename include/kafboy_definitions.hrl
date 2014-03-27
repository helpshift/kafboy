%%======================================================================
%% Defaults
%%======================================================================
-define(KAFBOY_DEFAULT_SYNC_URL        , "/sync/:topic/").
-define(KAFBOY_DEFAULT_ASYNC_URL       , "/async/:topic/").
%%======================================================================
%% Debugging Toggles
%%======================================================================
-define(KAFBOY_VERSION                 , 0.1).


%%======================================================================
%% Macros
%%======================================================================
-define(INFO_MSG(Format, Args),
    case application:get_env(kafboy,enable_logging) of
         {ok,true} ->
            lager:info
              ("~p:~p ~p:"++Format, [?MODULE, ?LINE, self()]++Args);
        _ ->
            io:format
          ("~n~p:~p ~p:"++Format, [?MODULE, ?LINE, self()]++Args)
    end
       ).

-define(ERROR_MSG(Format, Args),
        case application:get_env(kafboy,enable_logging) of
            {ok,true} ->
                lager:error("~p:~p "++Format++"~n~p", [?MODULE, ?LINE]++Args++[erlang:get_stacktrace()]);
        _ ->
                io:format("~n{~p:~p ~p}:"++Format++"~n~p", [?MODULE, ?LINE, self()]++Args++[erlang:get_stacktrace()])
    end
       ).

-define(DEBUG_MSG(Format, Args),
        case application:get_env(kafboy,enable_logging) of
            {ok,true} ->
                lager:debug(Format,Args);
            _ ->
                ok
        end
       ).

-define(record_to_list(Rec, Ref), lists:zip(record_info(fields, Rec),tl(tuple_to_list(Ref)))).

-include("kafboy_records.hrl").
%%======================================================================
%% Database

%%======================================================================
%% Security
%%======================================================================
-define(KAFBOY_DEFAULT_COOKIE_ERLANG,<<"afkak">>).
%-include("kafboy_creds.hrl").

%%======================================================================
%% Configs
%%======================================================================
-define(KAFBOY_AUTOSTART, true).
-define(TCP_DEFAULT_SEND_OPTIONS,[{active, once},{nodelay,true},{keepalive,true},{broadcast,false}]).
%%======================================================================
%% set/get Keys
%%======================================================================
-define(KAFKA_STATSS_NS      , <<"kafboy">>).

%%-include("kaboy_literals.hrl").
