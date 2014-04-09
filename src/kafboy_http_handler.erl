%% @doc
%% web server that allows editing the json before sending to kafka
%% @end
-module(kafboy_http_handler).
-behaviour(cowboy_loop_handler).
-export([init/3]).
-export([handle/2, handle_method/3, handle_url/4, info/3]).
-export([terminate/3]).

-export([test_callback_edit_json/2]).

%% includes
-include("kafboy_definitions.hrl").
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

test_callback_edit_json(PropList,Callback)->
    Callback(PropList).

init(_Transport, Req, InitState) ->
    {Method, _} = cowboy_req:method(Req),
    handle_method(Method, Req, InitState).

%% if not safe, then directly call handle_edit_json_callback
%% if safe, then safetyvalve is called if sv thinks its ok
handle_method(<<"POST">>, Req, #kafboy_http{ safe = false } = State)->
    {ok, Body, _} = cowboy_req:body_qs(Req),
    handle_edit_json_callback(Body, Req, State);

handle_method(<<"POST">>, Req, State)->
    {ok, Body, _} = cowboy_req:body_qs(Req),
    case sv:run(kafboy_q, fun() ->
                                  handle_edit_json_callback(Body, Req, State)
                          end) of
        {ok,Next} ->
            Next;
        {error, queue_full} = Error->
            ?INFO_MSG("error, queue_full",[]),
            {ok, Req, Error};
        {error, overload} = Error ->
            ?INFO_MSG("error, queue_overload",[]),
            {ok, Req, Error}
    end;
handle_method(_, Req, State)->
   fail(<<"unexp">>, Req, State).

handle_edit_json_callback(Body, Req, #kafboy_http{ callback_edit_json = Callback} = State)->
    case Callback of
        {M,F} when is_atom(M), is_atom(F)->
            NextCallback = fun(NextBody)->
                               self() ! {edit_json_callback, NextBody}
                       end,
            M:F(Body,NextCallback);
        _ ->
            %?INFO_MSG("no callback , just send",[]),
            self() ! {edit_json_callback, Body}
    end,
    {loop, Req, State, 1000}.

handle(Req, {error,queue_full}=State)->
    fail(<<"system queue full">>, Req, State);
handle(Req, {error,overload}=State)->
    fail(<<"system overload">>, Req, State);
handle(Req, State)->
    {Method, _} = cowboy_req:method(Req),
    handle_method(Method, Req, State).

fail(Msg, Req, State) ->
    ?INFO_MSG("handle ~s",[Msg]),
    {ok, Req1} = cowboy_req:reply(503, [], <<"Unexpected">>, Req),
    {ok, Req1, State}.

info({edit_json_callback,[]}, Req, State)->
    Req1 = reply("{\"error\":\"empty\"}",Req),
    {ok, Req1, State};
info({edit_json_callback,Body}, Req, State)->
    %% Produce to topic

    %% See bosky101/ekaf for what happens under the hood
    %% connection pooling, batched writes, and so on

    {ok,Req1} =
        case cowboy_req:path(Req) of
            {Url,_} ->
                handle_url(Url, Body, Req, State);
            _Path ->
                ?INFO_MSG("dont know what to do with ~p",[_Path]),
                reply("{\"error\":\"invalid\"}",Req)
        end,
    {ok, Req1, State};
info(Message, Req, State) ->
    ?INFO_MSG("unexp ~p",[Message]),
    {ok,Req1} = reply("{\"error\":\"invalid\"}",Req),
    {ok, Req1, State}.

handle_url(<<"/safe/",Url/binary>>, Body, Req, State)->
     handle_url(<<"/",Url/binary>>, Body, Req, State);
handle_url(Url, Body, Req, _State)->
    Json = jsx:encode(Body),
    case Url of
        <<"/sync/",Topic/binary>> ->
            ProduceResponse = kafboy_producer:sync(Topic, Json, []),
            %% in case you want to create your own list, see the below function
            ResponseList = ekaf_lib:response_to_proplist(ProduceResponse),
            ResponseJson = jsx:encode(ResponseList),
            reply(ResponseJson,Req);

        <<"/batch/sync/",Topic/binary>> ->
            _ProduceResponse = kafboy_producer:sync_batch(Topic, Json, []),
            reply("{\"ok\":true}",Req);

        <<"/async/",Topic/binary>> ->
            _ProduceResponse = kafboy_producer:async(Topic, Json, []),
            reply("{\"ok\":true}",Req);

        <<"/batch/async/",Topic/binary>> ->
            _ProduceResponse = kafboy_producer:async_batch(Topic, Json, []),
            reply("{\"ok\":true}",Req);

        _Path ->
            ?INFO_MSG("dont know what to do with ~p",[_Path]),
            reply("{\"error\":\"invalid\"}",Req)
    end.

terminate(_Reason, _Req, _State) ->
    ok.

reply(Json,Req)->
    cowboy_req:reply(200,[{<<"content-type">>, <<"application/json; charset=utf-8">>}], Json, Req).
