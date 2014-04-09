%%%-------------------------------------------------------------------
%%% @doc produce to kafka
%%% @end
%%%-------------------------------------------------------------------
-module(kafboy_producer).

-include("kafboy_definitions.hrl").

-export([sync/3,async/3,
        sync_batch/3, async_batch/3]).

sync(Topic,Data,_Opts) ->
    ekaf:produce_sync(Topic, Data).

sync_batch(Topic,Data,_Opts)->
    ekaf:produce_sync_batched(Topic, Data).

async(Topic,Data,_Opts) ->
    ekaf:produce_async(Topic, Data).

async_batch(Topic,Data,_Opts)->
    ekaf:produce_async_batched(Topic, Data).
