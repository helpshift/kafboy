-module(kafboy_logger).

-compile([export_all]).

%% includes
-include("kafboy_definitions.hrl").
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

log(Format,Args)->
    ?INFO_MSG(Format,Args).

info_msg(Mod,Line,Format,Args)->
    lager:info(Format,Args).

enabled_modules()->
    [
     %kafboy_http_handler
    ].

enabled_functions()->
    ['_'].

enable_module(Mod)->
    gen_server:call(kafboy_startup_worker,{log,enable_module,Mod}).

disable_module(Mod)->
    gen_server:call(kafboy_startup_worker,{log,disable_module,Mod}).
