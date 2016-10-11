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
-include("gen_netlink/include/netlink.hrl").
-include("gen_socket/include/gen_socket.hrl").

-export([start_link/0]).

-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
        socket :: gen_socket:socket()
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
    %%  genl_init_handle(&grth, TCP_METRICS_GENL_NAME, &genl_family)
    %%  genl_family = 24
    %%  req.n.nlmsg_type = genl_family;
    %%  cmd = 1
    %%  req.n.nlmsg_flags = 1 | NLM_F_DUMP;
    %%  req.n.nlmsg_flags  = 769
    %%  req.n.nlmsg_seq = grth.dump = ++grth.seq %% timestamp

    {ok, Socket} = socket(netlink, raw, ?NETLINK_NETFILTER, []),
    {gen_socket, RealPort, _, _, _, _} = Socket,
    erlang:link(RealPort),
    ok = gen_socket:bind(Socket, netlink:sockaddr_nl(netlink, 0, 0)),
    ok = gen_socket:setsockopt(Socket, ?SOL_SOCKET, ?SO_RCVBUF, 1024*1024),
    netlink:rcvbufsiz(Socket, ?RCVBUF_DEFAULT),
    ok = gen_socket:input_event(Socket, true),
    erlang:send_after(splay_ms(), self(), poll_tcp_metrics),
    GetFamily = #getfamily{request = <<"tcp_metrics">>},
    Payload = nl_enc_payload({netlink, generic}, ?NLM_F_REQUEST, GetFamily),
    {ok, #state{socket = Socket}}.

-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
    {reply, Reply :: term(), NewState :: #state{}} |
    {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
    {stop, Reason :: term(), NewState :: #state{}}).
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
   
handle_info({Socket, input_ready}, State = #state{socket = Socket}) ->
    {noreply, State}.
handle_info(poll_tcp_metrics, State) ->
    {noreply, State}.
handle_info(_Info, State) ->
    {noreply, State}.

-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, State = #state{socket = Socket}) ->
    gen_socket:close(Socket),
    ok.

-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
    {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% TODO: borrowed from minuteman, should probably be a util somewhere
-spec(splay_ms() -> integer()).
splay_ms() ->
    MsPerMinute = tcp_metrics_config:interval_seconds() * 1000,
    NextMinute = -1 * erlang:monotonic_time(milli_seconds) rem MsPerMinute,
    SplayMS = tcp_metrics_config:splay_seconds() * 1000,
    FlooredSplayMS = max(1, SplayMS),
    Splay = rand:uniform(FlooredSplayMS),
    NextMinute + Splay.
