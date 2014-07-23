%% @copyright 2014 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc TODO
-module(mqttc_session_tests).

-include_lib("eunit/include/eunit.hrl").
-on_load(start_app/0).

%%------------------------------------------------------------------------------------------------------------------------
%% On Load
%%------------------------------------------------------------------------------------------------------------------------
start_app() ->
    {ok, _} = application:ensure_all_started(mqttc),
    _ = error_logger:tty(false),
    ok.

%%------------------------------------------------------------------------------------------------------------------------
%% Macros
%%------------------------------------------------------------------------------------------------------------------------
-define(CLIENT_ID, <<"hoge">>).

-define(assertDownWithoutMonitor(Pid, ExpectedReason),
        (fun () ->
                 receive {'DOWN', _, _, Pid, Reason} -> ?assertMatch(ExpectedReason, Reason) after 100 -> ?assert(timeout) end
         end)()).

-define(assertDown(Pid, ExpectedReason),
        (fun () ->
                 monitor(process, Pid),
                 ?assertDownWithoutMonitor(Pid, ExpectedReason)
         end)()).

%%------------------------------------------------------------------------------------------------------------------------
%% Unit Tests
%%------------------------------------------------------------------------------------------------------------------------
start_and_stop_test_() ->
    [
     {"Starts anonymous process",
      fun () ->
              Name = undefined, % anonymous

              %% start
              Result = mqttc_session:start_link({Name, self(), ?CLIENT_ID}),
              ?assertMatch({ok, _}, Result),
              {ok, Pid} = Result,

              %% stop
              ok = mqttc_session:stop(Pid),

              ?assertDown(Pid, normal)
      end},
     {"Starts named process",
      fun () ->
              Name = hogehoge,

              %% start
              Result = mqttc_session:start_link({{local, Name}, self(), ?CLIENT_ID}),
              ?assertMatch({ok, _}, Result),
              {ok, Pid} = Result,

              %% name conflict
              ?assertEqual({error, {already_started, Pid}}, mqttc_session:start_link({{local, Name}, self(), ?CLIENT_ID})),

              %% stop by name
              ok = mqttc_session:stop(Name),

              ?assertDown(Pid, normal)
      end},
     {"Starts process with linked owner",
      fun () ->
              Name = undefined, % anonymous
              OwnerPid = spawn(timer, sleep, [infinity]),

              %% start
              {ok, SessionPid} = mqttc_session:start_link({Name, {link, OwnerPid}, ?CLIENT_ID}),
              true = unlink(SessionPid),

              monitor(process, SessionPid),
              monitor(process, OwnerPid),
              exit(SessionPid, something_wrong),
              
              ?assertDownWithoutMonitor(SessionPid, something_wrong),
              ?assertDownWithoutMonitor(OwnerPid, something_wrong) % OwnerPid has been linked to SessionPid
      end},
     {"Started process is linked to caller process",
      fun () ->
              ParentPid = self(),
              CallerPid = spawn(fun () ->
                                        {ok, Pid} = mqttc_session:start_link({undefined, self(), ?CLIENT_ID}),
                                        ParentPid ! {session, Pid},
                                        timer:sleep(infinity)
                                end),
              receive {session, SessionPid} -> ok end,

              monitor(process, CallerPid),
              monitor(process, SessionPid),
              exit(CallerPid, something_wrong),

              ?assertDownWithoutMonitor(CallerPid, something_wrong),
              ?assertDownWithoutMonitor(SessionPid, something_wrong)
      end},
     {"Stops non existing process",
      fun () ->
              Pid = spawn(fun () -> timer:sleep(5) end),
              ?assertDown(Pid, normal),

              ?assertEqual(ok, mqttc_session:stop(Pid)) % no error
      end}
    ].

get_session_status_test_() ->
    [
     {"session status: disconnected",
      fun () ->
              {ok, Pid} = mqttc_session:start_link({undefined, self(), ?CLIENT_ID}),
              ?assertEqual(disconnected, mqttc_session:get_status(Pid))
      end}
    ].

get_client_id_test() ->
    {ok, Pid} = mqttc_session:start_link({undefined, self(), ?CLIENT_ID}),
    ?assertEqual(?CLIENT_ID, mqttc_session:get_client_id(Pid)).

connect_test_() ->
    [
     {"basic connect",
      fun () ->
              {ok, Pid} = mqttc_session:start_link({undefined, self(), ?CLIENT_ID}),
              ?assertEqual(ok, mqttc_session:connect(Pid, <<"localhost">>, 1883, [], 500)),
              ?assertEqual(connected, mqttc_session:get_status(Pid))
      end},
     {"duplicated connect request",
      fun () ->
              {ok, Pid} = mqttc_session:start_link({undefined, self(), ?CLIENT_ID}),
              ok = mqttc_session:connect(Pid, <<"localhost">>, 1883, [], 500),
              connected = mqttc_session:get_status(Pid),

              ?assertEqual({error, {mqtt_error, connect, connected}}, mqttc_session:connect(Pid, <<"localhost">>, 1883, [], 500)),
              ?assertEqual(connected, mqttc_session:get_status(Pid))
      end},
     %% {"tcp timeout",
     %%  fun () ->
     %%          {ok, Pid} = mqttc_session:start_link({undefined, self(), ?CLIENT_ID}),
     %%          ?assertEqual(ok, mqttc_session:connect(Pid, <<"localhost">>, 1883, [{tcp_timeout, 1}], 500)),
     %%          ?assertEqual(connected, mqttc_session:get_status(Pid))
     %%  end}
     {"unknown host",
      fun () ->
              {ok, Pid} = mqttc_session:start_link({undefined, self(), ?CLIENT_ID}),
              ?assertMatch({error, {tcp_error, connect, _maybe_nxdomain}}, mqttc_session:connect(Pid, <<"hogehoge">>, 1883, [{tcp_timeout, 10}], 500))
      end}
    ].

disconnect_test_() ->
    [
     {"invoke disconnect request to non connected session",
      fun () ->
              {ok, Pid} = mqttc_session:start_link({undefined, self(), ?CLIENT_ID}),
              ?assertEqual(disconnected, mqttc_session:get_status(Pid)),
              ?assertEqual({error, {mqtt_error, disconnect, disconnected}}, mqttc_session:disconnect(Pid, 500))
      end},
     {"disconnect connected session",
      fun () ->
              {ok, Pid} = mqttc_session:start_link({undefined, self(), ?CLIENT_ID}),
              ok = mqttc_session:connect(Pid, <<"localhost">>, 1883, [], 500),
              connected = mqttc_session:get_status(Pid),

              ?assertEqual(ok, mqttc_session:disconnect(Pid, 500)),
              ?assertEqual(disconnected, mqttc_session:get_status(Pid))
      end},
     {"reconnect after disconnection",
      fun () ->
              {ok, Pid} = mqttc_session:start_link({undefined, self(), ?CLIENT_ID}),
              ok = mqttc_session:connect(Pid, <<"localhost">>, 1883, [], 500),
              connected = mqttc_session:get_status(Pid),

              ok = mqttc_session:disconnect(Pid, 500),
              disconnected = mqttc_session:get_status(Pid),

              ok = mqttc_session:connect(Pid, <<"localhost">>, 1883, [], 500),
              connected = mqttc_session:get_status(Pid)
      end}
    ].
