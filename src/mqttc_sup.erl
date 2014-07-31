%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc application supervisor module
%% @private
-module(mqttc_sup).

-behaviour(supervisor).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported API
%%------------------------------------------------------------------------------------------------------------------------
-export([start_link/0]).

%%------------------------------------------------------------------------------------------------------------------------
%% 'application' Callback API
%%------------------------------------------------------------------------------------------------------------------------
-export([init/1]).

%%------------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%------------------------------------------------------------------------------------------------------------------------
%% @doc Starts supervisor process
-spec start_link() -> {ok, pid()} | {error, Reason::term()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%%------------------------------------------------------------------------------------------------------------------------
%% 'application' Callback Functions
%%------------------------------------------------------------------------------------------------------------------------
%% @private
init([]) ->
    ConnectionSup = mqttc_conn_sup,
    SessionSup = mqttc_session_sup,
    Children =
        [
         {ConnectionSup, {ConnectionSup, start_link, []}, permanent, 5000, supervisor, [ConnectionSup]},
         {SessionSup, {SessionSup, start_link, []}, permanent, 5000, supervisor, [SessionSup]}
        ],
    {ok, { {one_for_one, 5, 10}, Children} }.
