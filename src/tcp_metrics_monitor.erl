%%%-------------------------------------------------------------------
%%% @author Anatoly Yakovenko
%%% @copyright (C) 2015, Mesosphere
%%% @doc
%%%
%%% @end
%%% Created : 03. Oct 2016 11:44 AM
%%%-------------------------------------------------------------------
-module(tcp_metrics_monitor).
-author("Anatoly Yakovenko").

-behaviour(gen_server).
-include_lib("gen_netlink/include/netlink.hrl").

-export([get_metrics/0]).
-export([start_link/0]).

-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).

-type link_info() :: [#netlink{}].
-type network_ns() :: string().
-type metrics() :: #{network_ns() := link_info()}.

-record(state, {
        family :: integer(),
        metrics = #{} :: metrics()
    }).

-spec(start_link() ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

-spec(init(term()) ->
    {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |

    {stop, Reason :: term()} | ignore).
init([]) ->
    process_flag(trap_exit, true),
    {ok, Family} = get_family(),
    erlang:send_after(splay_ms(), self(), poll_tcp_metrics),
    {ok, #state{family = Family}}.

-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
    {reply, Reply :: term(), NewState :: #state{}} |
    {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_call(get_metrics, _From, State) ->
    {reply, {ok, State#state.metrics}, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

-spec(handle_cast(Request :: term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(_Request, State) ->
    {noreply, State}.

-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_info(poll_tcp_metrics, State = #state{family = Family}) ->
    Start = erlang:monotonic_time(micro_seconds),
    Metrics = get_metrics_from_proc(Family),
    End = erlang:monotonic_time(micro_seconds),
    erlang:send_after(splay_ms(), self(), poll_tcp_metrics),
    NewState = State#state{metrics = Metrics},
    {noreply, NewState};
handle_info(_Info, State) ->
    {noreply, State}.

-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State = #state{}) ->
    ok.

-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
    {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


-spec(get_family() -> {ok, integer()} | {error, term() | string() | binary()}).
get_family() ->
    {ok, Socket} = procket:socket(netlink, dgram, ?NETLINK_GENERIC),
    Pid = 0,
    Seq = erlang:unique_integer([positive]),
    Flags = [ack, request],
    Payload = #getfamily{request = [{family_name, "tcp_metrics"}]},
    Msg = {netlink, ctrl, Flags, Seq, Pid, Payload},
    Data = netlink_codec:nl_enc(generic, Msg),
    SndRsp = procket:sendto(Socket, Data),
    RecvRsp = procket:recv(Socket, 4*1024),
    procket:close(Socket),
    ok = SndRsp,
    {ok, Rsp} = RecvRsp,
    Decoded = netlink_codec:nl_dec(?NETLINK_GENERIC, Rsp),
    [#netlink{seq = Seq, msg = {newfamily,_,_, Attrs}}] = Decoded,
    {family_id, Family} = lists:keyfind(family_id, 1, Attrs),
    {ok, Family}.

-spec(get_metrics() -> metrics()).
get_metrics() -> gen_server:call(?SERVER, get_metrics).

-spec(get_metrics_from_socket(integer(), {ok, integer()} | {error, term()}) -> [term()]).
get_metrics_from_socket(Family, {ok, Socket}) ->
    Pid = 0,
    Seq = erlang:unique_integer([positive]),
    Flags = [?NLM_F_DUMP, request],
    Msg = {netlink, tcp_metrics, Flags, Seq, Pid, {get, 1, 0, []}},
    Data = netlink_codec:nl_enc(Family, Msg),
    SndRsp = procket:sendto(Socket, Data),
    RecvRsp = procket:recv(Socket, 64*1024),
    procket:close(Socket),
    ok = SndRsp,
    {ok, Rsp} = RecvRsp,
    Decoded = netlink_codec:nl_dec(tcp_metrics, Rsp),
    [Decoded];
get_metrics_from_socket(_, _) -> [].

get_metrics_from_proc(Family) ->
    {ok, Pids} = file:list_dir("/proc"),
    Metrics = lists:foldl(
                fun(Pid, Map) ->
                        PidInt = string:to_integer(Pid),
                        get_metrics_from_ns(Family, PidInt, Map)
                end,
                maps:new(), Pids),
    Metrics.

get_metrics_from_ns(_Family, {error, _}, Map) -> Map;
get_metrics_from_ns(Family, {PidInt, _}, Map) ->
    PidStr = integer_to_list(PidInt),
    NetNs = "/proc/" ++ PidStr ++ "/ns/net",
    NetNsInfo = file:read_link_all(NetNs),
    get_metrics_from_ns(Family, PidStr, NetNsInfo, Map).

get_metrics_from_ns(Family, PidStr, {ok, NetNs}, Map) ->
    get_metrics_from_ns(Family, PidStr, NetNs, maps:get(NetNs, Map, unknown), Map);
get_metrics_from_ns(_Family, _PidStr, _, Map) -> Map.

get_metrics_from_ns(Family, PidStr, NetNs, unknown, Map) ->
    Opts = [{family, netlink},
            {protocol, ?NETLINK_GENERIC},
            {type,dgram},
            {progname, "nsenter -t " ++ PidStr ++ " -n ../../lib/procket/priv/procket"}],
    Socket = procket:open(0, Opts),
    Metrics = get_metrics_from_socket(Family, Socket),
    update_map(NetNs, Metrics, Map);
get_metrics_from_ns(_Family, _PidStr, _NetNs, _, Map) -> Map.

%% last value in Ls ends up in the Key 
%% we only expect [] or [Val]
update_map(Key, Ls, Map) ->
    lists:foldl(fun(L, Z) ->
                        maps:put(Key, L, Z)
                end,
                Map, Ls).

%% TODO: borrowed from minuteman, should probably be a util somewhere
-spec(splay_ms() -> integer()).
splay_ms() ->
    MsPerMinute = tcp_metrics_config:interval_seconds() * 1000,
    NextMinute = -1 * erlang:monotonic_time(milli_seconds) rem MsPerMinute,
    SplayMS = tcp_metrics_config:splay_seconds() * 1000,
    FlooredSplayMS = max(1, SplayMS),
    Splay = rand:uniform(FlooredSplayMS),
    NextMinute + Splay.

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

update_map_test_() ->
    [?_assertEqual(#{}, update_map(hello, [], #{})),
     ?_assertEqual(#{hello => world}, update_map(hello, [world], #{})),
     ?_assertEqual(#{hello => moon}, update_map(hello, [world, moon], #{}))].

handle_bad_socket_test_() ->
    [?_assertEqual([], get_metrics_from_socket(1, {error, foobar}))].

normal_socket_test_() ->
    {ok, Family} = get_family(),
    {ok, Socket} = procket:socket(inet6, stream, tcp),
    SA = list_to_binary([procket:sockaddr_common(inet6, 128), <<0:16/integer-unsigned-big, 0:((128 - (2+2))*8)>>]),
    ok = procket:bind(Socket, SA),
    {Sz, RA} = procket:getsockname(Socket, SA),
    io:format("listen address ~p ~p\n", [Sz,RA]),
    ok = procket:listen(Socket, 1),
    {ok, Send} = procket:socket(inet6, stream, tcp),
    procket:connect(Send, RA),
    {ok, Recv} = procket:accept(Socket),
    Attrs = [{d_addr,{54,192,147,29}},
             {s_addr,{10,0,79,182}},
             {age_ms,806101408},
             {vals,[{rtt_us,47313},
                    {rtt_ms,47},
                    {rtt_var_us,23656},
                    {rtt_var_ms,23},
                    {cwnd,10}]}],
    Msg = [{netlink,tcp_metrics, [multi], 18,31595, {get,1,0,Attrs}}],
    Buf = netlink_codec:nl_enc(Family, Msg),
    io:format("message ~p\n", [Buf]),
    procket:sendto(Send, Buf),
    [?_assertEqual([Msg], get_metrics_from_socket(Family, {ok, Recv}))].

handle_alredy_found_ns_test_() ->
    [?_assertEqual(#{hello => world}, get_metrics_from_ns(1, "2", "net[213423]", world, #{hello => world}))].

-endif.
