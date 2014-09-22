# kafboy

a low latency http server for writing to kafka. Optimized for heavy loads, hundreds of partition workers, supports batching, and more. Written in Erlang. Powered by `ekaf` and `Cowboy`

![ordered_round_robin](/benchmarks/n30000_c100_strategy_random.png)
*see https://github.com/helpshift/ekaf for more information*

## Architecture

With 0.8, Kafka clients take greater responsibility of deciding which broker and partition to publish to for a given topic.

kafboy is a http wrapper over the ekafka client, that takes care of routing http requests to the right kafka broker socket. kafboy is self-aware over a cluster, and supoprts nodes routing requests arriving on any node, to the right process in the cluster.

Simply send a POST with the desired JSON, to one of the following paths

## Fire and forget

    % fire and forget asynchronous call. the event is immediately send to kafka asynchronously
    POST /async/topic

## Synchronous calls

    % synchronous call that returns with the response after sending to kafka
    % `NOTE: a reply is sent until after kafka resonds, so is not recommended for low latency needs`
    POST /sync/topic

## Batching

    % will be added to a queue, and sent to the broker in a batch.
    % batch size, and flush timeout are configurable
    POST /batch/async/topic

    % Use `safetyvalve` to limit performance degrade
    POST /safe/async/topic
    POST /safe/sync/topic
    POST /safe/batch/async/topic
    POST /safe/batch/sync/topic

The payload is expected to be of the JSON format, but this can be configured to send the data as is.
Very little else is done by this server in terms of dealing with kafka. It simply calls ekafka's produce function.

## Safe urls

Requests that begin with /safe/ will look for a `safetyvalve` entry to make the most of safetyvalve's ability to handle overload.

Here is an example safetyvalve entry expected

     %Note: You will have to add safetyvalve to your rebar.config or release as a dependency
     %      for /safe/ urls to function as expected
     {safetyvalve,
         [{queues, [
             {kafboy_q, [{hz, 50}, {rate, 1000}, {token_limit, 10000}, {size, 300000}, {concurrency, 300000}]}]
         }
     ]}

## Configuring kafboy

    {kafboy,[
        % optional. you get to edit the json before it goes to kafka over here
        {kafboy_callback_edit_json, {my_module, massage_json}},
        % M:F({post, Topic, Req, Json, Callback}) will be called. return with what you want to send to kafka
        % if an error occurs M:F({error, StatusCode, Message}) wil be called

        % optional.
        {kafboy_enable_safetyvalve, false},
        % Not enabled by default

        % optional.
        {kafboy_load_balancer, "http://localhost:8080/disco"}
        % should return plaintext of a node name with the right cookie eg: `node2@some-host`
        % can be used to distribute work to other nodes if ekaf thinks this one is too busy
    ]}

In this example, you have to implement my_module:massage_json/1, on the lines of

    massage_json({post, Topic, Req, Body, Callback})->
        Callback ! { edit_json_callback, Topic, Body }.


Here is a more elaborate example:

    %% Let's check for the contents of Body
    %% and if its valid, add an extra field
    %% and then submit to kafka
    massage_json({post, Topic, Req, Body, Callback})->
        case Body of
            [{<<"test">>},<<"a">>}] ->
                % either reply like this
                Callback ! { edit_json_callback, Topic, [{<<"a">>,<<"apple"}] };
            [] ->
                Calback ! {error, <<"you cant send empty">>};
            _ ->
                %% i want to first reply
                Callback ! { 200, <<"fast reply">>},

                %% then directly call ekaf
                Final = jsx:encode([{<<"extra">>,<<"true">>}| Body]),
                ekaf:produce_async_batched(Topic, Final)
        end.

kafboy will handle sending batch requests where the batch size is configurable, disconnections with brokers, and max retries.

To see the API of ekaf, see http://github.com/helpshift/ekaf


## Configuring ekaf

#### An example ekaf config

    {ekaf,[

        % required.
        {ekaf_bootstrap_broker, {"localhost", 9091} },
        % pass the {BrokerHost,Port} of atleast one permanent broker. Ideally should be
        %       the IP of a load balancer so that any broker can be contacted


        % required
        {ekaf_bootstrap_topics, [ <<"topic">> ]},

        % optional
        {ekaf_per_partition_workers,100},
        % how big is the connection pool per partition
        % eg: if the topic has 3 partitions, then with this eg: 300 workers will be started


        % optional
        {ekaf_max_buffer_size, [{<<"topic">>,10000},                % for specific topic
                                {ekaf_max_buffer_size,100}]},       % for other topics
        % how many events should the worker wait for before flushing to kafka as a batch


        % optional
        {ekaf_partition_strategy, random}
        % if you are not bothered about the order, use random for speed
        % else the default is ordered_round_robin


    ]},

To see how to configure the number of workers per topic+partition, the buffer batch size, buffer flush ttl, and more see the extensive README for `ekaf` https://github.com/helpshift/ekaf

## License

```
Copyright 2014, Helpshift, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

Add a feature request at https://github.com/helpshift/ekaf or check the ekaf web server at https://github.com/helpshift/kafboy
