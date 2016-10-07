-module(tcp_metrics_SUITE).
-compile(export_all).

-include_lib("common_test/include/ct.hrl").

all() -> [test_gen_server].

test_gen_server(_Config) ->
    erlang:send(tcp_metrics_monitor, hello),
    ok = gen_server:call(tcp_metrics_monitor, hello),
    ok = gen_server:cast(tcp_metrics_monitor, hello),
    sys:suspend(tcp_metrics_monitor),
    sys:change_code(tcp_metrics_monitor, random_old_vsn, tcp_metrics_monitor, []),
    sys:resume(tcp_metrics_monitor).

init_per_testcase(_, Config) ->
    {ok, _} = application:ensure_all_started(tcp_metrics),
    Config.

end_per_testcase(_, _Config) ->
    ok = application:stop(tcp_metrics).


