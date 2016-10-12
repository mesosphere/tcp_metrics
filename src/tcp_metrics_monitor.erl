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

-export([start_link/0]).

-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).

%% -define(GENL_ID_GENERATE    ,0).
%% -define(GENL_ID_CTRL        ,NETLINK_GENERIC).
%% -define(GENL_ID_VFS_DQUOT   ,(NETLINK_GENERIC + 1)).
%% -define(GENL_ID_PMCRAID     ,(NETLINK_GENERIC + 2)).
%% -define(NLM_F_ROOT          ,16#100).    %% specify tree    root
%% -define(NLM_F_MATCH         ,16#200).    %% return all matching
%% -define(NLM_F_ATOMIC        ,16#400).    %% atomic GET
%% -define(NLM_F_DUMP          ,(NLM_F_ROOT|NLM_F_MATCH)).


-record(state, {
        socket :: integer(),
        family :: integer()
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
    ct:pal("init tcp_metrics_monitor"),
    {ok, Socket} = procket:socket(netlink, dgram, ?NETLINK_GENERIC),
    ct:pal("init procket:open"),
    {ok, Family} = get_family(Socket),
    ct:pal("init get_family ~p", [Family]),
    {ok, #state{socket = Socket, family = Family}}.

-spec(get_family(integer()) -> {ok, integer()} | {error, term() | string() | binary()}).
get_family(Socket) ->
    ct:pal("get_family"),
    Pid = 0,
    Seq = erlang:unique_integer([positive]),
    Flags = [ack, request],
    Payload = #getfamily{request = [{family_name, "tcp_metrics"}]},
    Msg = {netlink, ctrl, Flags, Seq, Pid, Payload},
    Out = netlink_codec:nl_enc(generic, Msg),
    ct:pal("getfamily encoded ~p", [Out]),
    ok = procket:sendto(Socket, Out),
    ct:pal("getfamily sent!"),
    Rsp = procket:recv(Socket, 4*1024),
    ct:pal("getfamily response ~p", [Rsp]),
    case Rsp of
        {ok, Msg} ->
            Decoded = netlink_codec:nl_dec(?NETLINK_GENERIC, Msg),
            ct:pal("getfamily decoded ~p", [Decoded]),
            Decoded;
        Err ->
            ct:pal("getfamily error ~p", [Err]),
            Err
    end.

%% -spec(request_metrics(Pid :: integer(), Seq :: integer(), Socket :: gen_socket:socket()) -> ok | {error, term()}).
%request_metrics(Pid, Seq, Socket) ->
%    {gen_socket, RealPort, _, _, _, _} = Socket,
%    Flags = [ack, request],
%    Payload = gen_netlink:nl_enc({netlink, generic}, tcp_metrics, {get, 1, 0, 0}),
%    Msg = {netlink, ctrl, Flags, Seq, Pid, Payload},
%    ok = gen_socket:sendmsg(Socket, Payload),
%    receive
%        {Socket, input_ready} ->
%            Msg = gen_socket:recvmsg(Socket),
%            {ok, nl_dec_payload(Msg)}
%    after
%        Timeout -> {error, timeout} 
%    end.

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
    {noreply, State};
handle_info(poll_tcp_metrics, State) ->
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State = #state{socket = Socket}) ->
    procket:close(Socket),
    ok.

-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
    {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% TODO: borrowed from minuteman, should probably be a util somewhere
%% -spec(splay_ms() -> integer()).
%% splay_ms() ->
%%     MsPerMinute = tcp_metrics_config:interval_seconds() * 1000,
%%     NextMinute = -1 * erlang:monotonic_time(milli_seconds) rem MsPerMinute,
%%     SplayMS = tcp_metrics_config:splay_seconds() * 1000,
%%     FlooredSplayMS = max(1, SplayMS),
%%     Splay = rand:uniform(FlooredSplayMS),
%%     NextMinute + Splay.
