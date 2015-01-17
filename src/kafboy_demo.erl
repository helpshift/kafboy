-module(kafboy_demo).

-export([start/0, massage_json/1]).

-include_lib("kafkamocker/include/kafkamocker.hrl").

%% know where to curl to and for which topic
-define(TOPIC, <<"ekaf">>).
-define(KAFBOY_HTTP_PORT, 9903).

-define(USE_AN_ACTUAL_KAFKA_SERVER, false).
%% when set to false, uses the embedded kafkamocker

-define(KAFKAMOCKER_PORT, 9908).



massage_json({post, Topic, _Req, Body, CallbackPid})->
    case Body of
        [{<<"hello">>, Foo}] ->
            % either reply like this
            CallbackPid ! { edit_json_callback, Topic, Foo };
        [] ->
            CallbackPid ! {error, <<Topic/binary,".insufficient">>};
        _ ->
            %% i want to first reply
            CallbackPid ! { edit_json_callback, {200, <<"{\"ok\":\"fast reply\"}">>}},

            %% then directly call ekaf, adding this msg to a batch
            Final = jsx:encode([{<<"extra">>,<<"true">>}| Body]),
            ekaf:produce_async_batched(Topic, Final)
    end;
massage_json({error, Status, Message}) ->
    io:format("~n some ~p error: ~p",[Status, Message]),
    ok.

start()->
    Topic = ?TOPIC,
    [application:load(X) ||X<- [ekaf, kafkamocker, kafboy] ],

    %% mock a kafka server
    case ?USE_AN_ACTUAL_KAFKA_SERVER of
        true ->
            %% use your own actual broker
            application:set_env(ekaf, ekaf_bootstrap_broker, {"localhost", 9091});
        _ ->
            %% or mock it with an embedded kafkamocker
            application:set_env(ekaf, ekaf_bootstrap_broker, {"localhost", ?KAFKAMOCKER_PORT}),
            application:set_env(kafkamocker, kafkamocker_callback, kafka_consumer),
            application:set_env(kafkamocker, kafkamocker_bootstrap_broker, {"localhost",?KAFKAMOCKER_PORT}),
            application:set_env(kafkamocker, kafkamocker_bootstrap_topics, Topic),
            [ application:start(App) || App <- [gproc, ranch, kafkamocker]],
            kafkamocker_fsm:start_link({metadata, topics_metadata()})
    end,

    %% ekaf is the kafka client that kafboy internally uses
    %% more info on ekaf and its configuration at http://github.com/helpshift/ekaf
    application:set_env(ekaf, ekaf_per_partition_workers, 1),
    application:set_env(ekaf, ekaf_bootstrap_topics, Topic),
    application:set_env(ekaf, ekaf_buffer_ttl, 10),

    %% start kafboy
    %% every POST gets called into the callback massage_json
    %% it must also catch {error, Msg}, allowing you to log it, etc
    application:set_env(kafboy, kafboy_http_port, ?KAFBOY_HTTP_PORT),
    application:set_env(kafboy, kafboy_callback_edit_json, {?MODULE, massage_json}),

    %% ekaf needs groc, ranch, kafkamocker
    %% kafboy needs cowboy, cowlib, jsx
    [ application:start(App) || App <- [crypto, gproc, ranch, kafkamocker, ekaf, cowlib, cowboy, jsx, kafboy]].

topics_metadata()->
    Topics = [?TOPIC],
    #kafkamocker_metadata{
               brokers = [ #kafkamocker_broker{ id = 1, host = "localhost", port = 9908 }],
               topics =  [ #kafkamocker_topic { name = Topic,
                                                partitions = [ #kafkamocker_partition {id = 0, leader = 1,
                                                                                       replicas = [#kafkamocker_replica{ id = 1 }],
                                                                                       isrs = [#kafkamocker_isr{ id = 1 }]
                                                                                      }
                                                              ]
                                               }
                           || Topic <- Topics]}.
