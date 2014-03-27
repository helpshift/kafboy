%% @doc POST echo handler.
-module(kafboy_http_handler).

-export([init/3]).
-export([handle/2]).
-export([terminate/3]).


%% includes
-include("kafboy_definitions.hrl").
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

init(_Transport, Req, Opts) ->
    %?INFO_MSG("new request with options ~p",[Opts]),
    {ok, Req, Opts}.

handle(Req, State) ->
    {Method, Req2} = cowboy_req:method(Req),
    HasBody = cowboy_req:has_body(Req2),
    {ok, Req3} = maybe_echo(Method, HasBody, Req2, State),
    {ok, Req3, State}.

maybe_echo(<<"POST">>, true, Req, State) ->
    {ok, PostVals, Req2} = cowboy_req:body_qs(Req),
    echo(PostVals, Req2, State);
maybe_echo(<<"POST">>, false, Req, State) ->
    cowboy_req:reply(400, [], <<"Missing body.">>, Req);
maybe_echo(_, _, Req, State) ->
    %% Method not allowed.
    cowboy_req:reply(405, Req).

echo(Echo, Req, State) ->
    {Debug,_} = cowboy_req:qs_val(<<"DBG">>,Req,false),
    case Debug of
        <<"1">> ->
            io:format("~n for url: ~p reply with ~p ~nstate:~p",[cowboy_req:host_url(Req),Echo,State]);
        _ ->
            ok
    end,
    cowboy_req:reply(200, [
                           {<<"content-type">>, <<"application/json; charset=utf-8">>}
                          ], jsx:encode(Echo), Req).

terminate(_Reason, _Req, _State) ->
    ok.
