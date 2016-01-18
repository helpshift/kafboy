%% @doc /disco should return the current node
%% @end
-module(kafboy_disco_handler).

-include("kafboy_definitions.hrl").

-export([init/3,
         handle/2,
         handle_method/3,
         terminate/3]).

init(_Transport, Req, State) ->
    {ok, Req, State}.

handle(Req,State)->
    {Method, Req1} = cowboy_req:method(Req),
    {ok, Req2} = handle_method(Method, Req1, State),
    %%TODO common signature authentication
    {ok, Req2, State}.

handle_method(<<"POST">>, Req, _State)->
    Body = case cowboy_req:has_body(Req) of
               true ->
                   {ok, PostVals, _} = cowboy_req:body_qs(Req),
                   PostVals;
               _ ->
                   []
           end,
    Json = jsx:encode(Body),
    cowboy_req:reply(200, [
                           {<<"content-type">>, <<"application/json; charset=utf-8">>}
                          ], Json, Req);
handle_method(_, Req, _State)->
    cowboy_req:reply(200, [
                           {<<"content-type">>, <<"text/plain; charset=utf-8">>}
                          ], atom_to_list(node()), Req).

terminate(_Reason, _Req, _State) ->
    ok.
