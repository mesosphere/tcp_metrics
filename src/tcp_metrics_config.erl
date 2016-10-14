%%%-------------------------------------------------------------------
%%% @author Anatoly Yakovenko
%%% @copyright (C) 2015, Mesosphere
%%% @doc
%%%
%%% @end
%%% Created : 14. Oct 2016 10:57 AM
%%%-------------------------------------------------------------------
-module(tcp_metrics_config).
-author("Anatoly Yakovenko").

-export([interval_seconds/0,
         splay_seconds/0
         ]).

interval_seconds() ->
  application:get_env(tcp_metrics, interval_seconds, 60).

splay_seconds() ->
  application:get_env(tcp_metrics, splay_seconds, 10).
