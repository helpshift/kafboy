=kafboy==

a scalable http wrapper to write into kafka

==Architecture==

With 0.8, Kafka clients take greater responsibility of deciding which broker and partition to publish to for a given topic.

kafboy is a http wrapper over the ekafka client, that takes care of routing http requests to the right kafka broker socket. kafboy is self-aware over a cluster, and supoprts nodes routing requests arriving on any node, to the right process in the cluster.

==Internals==

Requests may land on one of the base urls. The default is /topic/<topic> but this can be configured.

    % fire and forget asynchronous call
    POST /async/topic/<topic>

    % synchronous call that returns with the response
    POST /sync/topic/<topic>

The payload is expected to be of the JSON format, but this can be configured to send the data as is.
Very little else is done by this server in terms of dealing with kafka. It simply calls ekafka's produce function.

== Buffering ==
kafboy will handle sending batch requests where the batch size is configurable, disconnections with brokers, and max retries.

The configurations are

    max_buffer_size, max_buffer_timeout, max_throughput
