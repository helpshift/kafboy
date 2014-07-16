%% @doc
%% web server that allows editing the json before sending to kafka
%% @end
-module(kafboy_http_handler).
-behaviour(cowboy_loop_handler).
-export([init/3]).
-export([handle/2, handle_method/3, handle_url/5, info/3]).
-export([terminate/3]).
-define(DEFAULT_HEADER,[{<<"content-type">>, <<"application/json; charset=utf-8">>}]).
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
    handle_edit_json_callback(Req, State);

handle_method(<<"POST">>, Req, State)->
    case sv:run(kafboy_q, fun() ->
                                  handle_edit_json_callback(Req, State)
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
handle_method(<<"GET">>, Req, State)->
    {ok, Req1, Next} = fail(<<"POST exp">>, Req, State),
    {loop, Req1, Next, 500};
handle_method(_, Req, State)->
    {ok,Req1,Next} = fail(<<"unexp">>, Req, State),
    {loop, Req1, Next, 500}.

handle_edit_json_callback(Req, #kafboy_http{ callback_edit_json = {M,F}} = State)->
    Self = self(),
    % NOTE: the cowboy_req:body_qs, and read buffer should be bound in the same proess
    %       filed an issue, got an explanation at
    %       https://github.com/extend/cowboy/issues/718
    ReqBody = cowboy_req:body_qs(Req),
    spawn(fun()->
                  case
                      ReqBody
                      of
                      {ok, Body, Req1} ->
                          {Topic, _} = cowboy_req:binding(topic, Req1),
                          NextCallback = fun(NextBody)->
                                                 Self ! {edit_json_callback, Topic, NextBody}
                                         end,
                          M:F({post, Topic, Req, Body, NextCallback});
                      _E ->
                          Self ! {edit_json_callback, {error,<<"no_body">>}}
                  end
          end),
    {loop, Req, State, 500};
%% No callback
handle_edit_json_callback(Req, State)->
    ReqBody = cowboy_req:body_qs(Req),
    Self = self(),
    case
        ReqBody
        of
        {ok, Body, Req1} ->
            {Topic, _} = cowboy_req:binding(topic, Req1),
            Self ! {edit_json_callback, Topic, Body};
        _ ->
            Self ! {edit_json_callback, {error,<<"no_body">>}}
    end,
    {loop, Req, State, 500}.

handle(Req, {error,queue_full}=State)->
    fail(<<"system queue full">>, Req, State);
handle(Req, {error,overload}=State)->
    fail(<<"system overload">>, Req, State);
handle(Req, {error,Msg}=State)->
    fail(Msg, Req, State);
handle(Req, State)->
    {Method, _} = cowboy_req:method(Req),
    handle_method(Method, Req, State).

fail({error,Msg}, Req, State) ->
    fail(Msg, Req, State);
fail(Msg, Req, #kafboy_http{ callback_edit_json = {M,F}} = _State) when is_binary(Msg) ->
    M:F({error, 500, Msg}),
    {ok,Req1} = cowboy_req:reply(500,?DEFAULT_HEADER, <<"{\"error\":\"",Msg/binary,"\"}">>, Req),
    {ok, Req1, undefined};
fail(_Msg, Req, #kafboy_http{ callback_edit_json = {M,F}} = _State) ->
    M:F({error, 500, _Msg}),
    Req1 = cowboy_req:reply(500, ?DEFAULT_HEADER, <<"{\"error\":\"unknown\"">>, Req),
    {ok, Req1, undefined}.

info({edit_json_callback,{200,Message}}, Req, _State)->
    reply(Message,Req);
info({edit_json_callback,{error,_}=Error}, Req, _State)->
    fail(Error,Req,_State);
info({edit_json_callback,[]}, Req, _State)->
    fail({error,<<"empty">>},Req, _State);
info({edit_json_callback, Topic, Body}, Req, State)->
    %% Produce to topic

    %% See bosky101/ekaf for what happens under the hood
    %% connection pooling, batched writes, and so on

    case cowboy_req:path(Req) of
        {Url,_} ->
            handle_url(Url, Topic, Body, Req, State);
        _Path ->
            ?INFO_MSG("dont know what to do with ~p",[_Path]),
            fail(<<"invalid">>,Req,State)
    end;
info(Message, Req, State) ->
    ?INFO_MSG("unexp ~p",[Message]),
    fail({error,<<"unexp">>}, Req, State).

handle_url(<<"/safe/",Url/binary>>, Topic, Body, Req, State)->
    handle_url(<<"/",Url/binary>>, Topic, Body, Req, State);
handle_url(_Url, _Topic, {error,Reason}, Req, State)->
    fail(Reason, Req, State);
handle_url(Url, Topic, Message, Req, State)->
    case Url of
        <<"/batch/async/",_/binary>> ->
            R = reply(<<"{\"ok\":1}">>,Req),
            spawn(fun()->
                          kafboy_producer:async_batch(Topic, Message, [])
                  end),
            R;
        <<"/batch/sync/",_/binary>> ->
            R = reply(<<"{\"ok\":1}">>,Req),
            spawn(fun()->
                          kafboy_producer:sync_batch(Topic, Message, [])
                  end),
            R;

        <<"/async/",_/binary>> ->
            R = reply(<<"{\"ok\":1}">>,Req),
            spawn(fun()->
                          kafboy_producer:async(Topic, Message, [])
                  end),
            R;

        <<"/sync/",_/binary>> ->
            ProduceResponse = kafboy_producer:sync(Topic, Message, []),
            %% in case you want to create your own list, see the below function
            ResponseList = ekaf_lib:response_to_proplist(ProduceResponse),
            ResponseJson = jsx:encode(ResponseList),
            reply(ResponseJson,Req);

        _Path ->
            ?INFO_MSG("dont know what to do with ~p",[_Path]),
            fail({error,<<"invalid">>},Req, State)
    end.

terminate(_Reason, _Req, _State) ->
    ok.

reply(Json,Req) when is_list(Json)->
    reply(ekaf_utils:atob(Json), Req);
reply(Json,Req)->
    {ok,Req1} = cowboy_req:reply(200,[{<<"content-type">>, <<"application/json; charset=utf-8">>}], Json, Req),
    {ok, Req1, undefined}.
