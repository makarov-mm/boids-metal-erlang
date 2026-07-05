%%% flock_server.erl — the simulation lives here, on the BEAM.
%%% A renderer (Swift/Metal or anything else) connects over TCP and
%%% receives binary frames at ~60 Hz:
%%%
%%%   frame  = count :: uint32-little
%%%          , count * boid
%%%   boid   = x :: float32-little, y, vx, vy         (16 bytes)
%%%
%%% Coordinates are normalized to [0,1] x [0,1].
%%% The client may send single-byte commands:
%%%   16#01 — chaos: kill a random boid (the supervisor restarts it)
%%%   16#02 — spawn one more boid
-module(flock_server).

-export([start/0, start/2]).

-define(TICK_MS, 16).

start() -> start(200, 4040).

start(N, Port) ->
    {ok, _Sup} = boid_sup:start_link(),
    [begin {ok, _} = boid_sup:spawn_boid(I) end || I <- lists:seq(1, N)],
    {ok, LSock} = gen_tcp:listen(Port, [binary,
                                        {packet, 0},
                                        {active, true},
                                        {reuseaddr, true},
                                        {nodelay, true}]),
    io:format("flock_server: ~p boids, listening on port ~p~n", [N, Port]),
    accept_loop(LSock).

accept_loop(LSock) ->
    {ok, Sock} = gen_tcp:accept(LSock),
    io:format("flock_server: renderer connected~n"),
    client_loop(Sock),
    io:format("flock_server: renderer disconnected~n"),
    accept_loop(LSock).

%%--------------------------------------------------------------------
client_loop(Sock) ->
    Snapshot = snapshot(),
    [gen_server:cast(Pid, {tick, Snapshot}) || {Pid, _, _, _, _} <- Snapshot],
    case gen_tcp:send(Sock, encode(Snapshot)) of
        ok ->
            receive
                {tcp, Sock, Data}    -> handle_commands(Data),
                                        client_loop(Sock);
                {tcp_closed, Sock}   -> ok;
                {tcp_error, Sock, _} -> ok
            after ?TICK_MS ->
                    client_loop(Sock)
            end;
        {error, _} ->
            ok
    end.

handle_commands(<<>>) -> ok;
handle_commands(<<16#01, Rest/binary>>) ->
    chaos(),
    handle_commands(Rest);
handle_commands(<<16#02, Rest/binary>>) ->
    {ok, _} = boid_sup:spawn_boid(extra),
    io:format("spawned extra boid, total ~p~n", [length(boids())]),
    handle_commands(Rest);
handle_commands(<<_, Rest/binary>>) ->
    handle_commands(Rest).

chaos() ->
    Bs = boids(),
    Victim = lists:nth(rand:uniform(length(Bs)), Bs),
    io:format("chaos: killing boid ~p~n", [Victim]),
    exit(Victim, kill).

%%--------------------------------------------------------------------
boids() ->
    [Pid || {_, Pid, _, _} <- supervisor:which_children(boid_sup)].

snapshot() ->
    %% A boid can die between which_children/1 and the call — that is
    %% not an error, it is the whole point. Skip it; the supervisor is
    %% already restarting it and it will appear in the next frame.
    lists:filtermap(
      fun(Pid) ->
              try {true, gen_server:call(Pid, get_state)}
              catch exit:_ -> false
              end
      end, boids()).

encode(Snapshot) ->
    Count = length(Snapshot),
    Body = << <<X:32/float-little, Y:32/float-little,
                VX:32/float-little, VY:32/float-little>>
              || {_Pid, X, Y, VX, VY} <- Snapshot >>,
    <<Count:32/unsigned-little, Body/binary>>.
