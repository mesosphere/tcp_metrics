-module(tcp_metrics_SUITE).
-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("gen_netlink/include/netlink.hrl").

all() -> [test_gen_server,
          test_wait,
          test_get_metrics].

test_gen_server(_Config) ->
    erlang:send(tcp_metrics_monitor, hello),
    ok = gen_server:call(tcp_metrics_monitor, hello),
    ok = gen_server:cast(tcp_metrics_monitor, hello),
    sys:suspend(tcp_metrics_monitor),
    sys:change_code(tcp_metrics_monitor, random_old_vsn, tcp_metrics_monitor, []),
    sys:resume(tcp_metrics_monitor).

test_wait(_Config) -> timer:sleep(2000).

test_get_metrics(_Config) -> test_get_metrics_ci(os:getenv("CI")).

test_get_metrics_ci(false) ->
    timer:sleep(2000),
    ct:pal("CI is ~p", [os:getenv("CI")]),
    {ok, Metrics} = tcp_metrics_monitor:get_metrics(),
    [H | _] = Metrics,
    ct:pal("got values ~p", [length(Metrics)]),
    #netlink{type = tcp_metrics} = H;

test_get_metrics_ci(_) ->
    timer:sleep(2000),
    ct:pal("CI is ~p", [os:getenv("CI")]),
    {ok, _} = tcp_metrics_monitor:get_metrics().

init_per_testcase(_, Config) ->
    application:set_env(tcp_metrics, interval_seconds, 1),
    application:set_env(tcp_metrics, splay_seconds, 1),
    {ok, _} = application:ensure_all_started(tcp_metrics),
    Config.

end_per_testcase(_, _Config) ->
    ok = application:stop(tcp_metrics).


