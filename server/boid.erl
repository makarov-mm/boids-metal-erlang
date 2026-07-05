%%% boid.erl — a single boid as an isolated Erlang process.
%%% Normalized world [0,1] x [0,1]; the renderer decides how to map it.
%%% Separation uses a bounded linear falloff instead of 1/d^2 so the
%%% forces stay predictable at any scale.
-module(boid).
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(W, 1.0).
-define(H, 1.0).
-define(PERCEPTION, 0.10).
-define(SEP_RADIUS, 0.025).
-define(MAX_SPEED, 0.008).
-define(MIN_SPEED, 0.003).
-define(W_SEP, 0.0020).
-define(W_ALI, 0.05).
-define(W_COH, 0.004).

-record(s, {x, y, vx, vy}).

%%--------------------------------------------------------------------
start_link(Id) ->
    gen_server:start_link(?MODULE, Id, []).

init(_Id) ->
    X  = rand:uniform() * ?W,
    Y  = rand:uniform() * ?H,
    A  = rand:uniform() * 2 * math:pi(),
    Sp = ?MIN_SPEED + rand:uniform() * (?MAX_SPEED - ?MIN_SPEED),
    {ok, #s{x = X, y = Y, vx = Sp * math:cos(A), vy = Sp * math:sin(A)}}.

%%--------------------------------------------------------------------
handle_call(get_state, _From, S = #s{x = X, y = Y, vx = VX, vy = VY}) ->
    {reply, {self(), X, Y, VX, VY}, S}.

handle_cast({tick, Neighbours}, S) ->
    {noreply, step(S, Neighbours)}.

handle_info(_, S) -> {noreply, S}.

%%--------------------------------------------------------------------
step(#s{x = X, y = Y, vx = VX, vy = VY}, All) ->
    Near = [{NX, NY, NVX, NVY}
            || {Pid, NX, NY, NVX, NVY} <- All,
               Pid =/= self(),
               dist(X, Y, NX, NY) < ?PERCEPTION],
    {AX, AY} = case Near of
                   []    -> {0.0, 0.0};
                   [_|_] -> steer(X, Y, VX, VY, Near)
               end,
    {VX2, VY2} = clamp_speed(VX + AX, VY + AY),
    #s{x = wrap(X + VX2, ?W), y = wrap(Y + VY2, ?H), vx = VX2, vy = VY2}.

steer(X, Y, VX, VY, Near) ->
    N = length(Near),
    {CX, CY} = fold2(fun({NX, NY, _, _}, {Ax, Ay}) -> {Ax + NX, Ay + NY} end, Near),
    {AVX, AVY} = fold2(fun({_, _, NVX, NVY}, {Ax, Ay}) -> {Ax + NVX, Ay + NVY} end, Near),
    %% separation: unit vector away, linear falloff, bounded
    {SepX, SepY} =
        fold2(fun({NX, NY, _, _}, {Ax, Ay}) ->
                      D = max(dist(X, Y, NX, NY), 1.0e-6),
                      case D < ?SEP_RADIUS of
                          true ->
                              F = (?SEP_RADIUS - D) / ?SEP_RADIUS,
                              {Ax + (X - NX) / D * F, Ay + (Y - NY) / D * F};
                          false -> {Ax, Ay}
                      end
              end, Near),
    {(CX / N - X) * ?W_COH + (AVX / N - VX) * ?W_ALI + SepX * ?W_SEP,
     (CY / N - Y) * ?W_COH + (AVY / N - VY) * ?W_ALI + SepY * ?W_SEP}.

fold2(F, L) -> lists:foldl(F, {0.0, 0.0}, L).

dist(X1, Y1, X2, Y2) ->
    DX = X1 - X2, DY = Y1 - Y2,
    math:sqrt(DX * DX + DY * DY).

clamp_speed(VX, VY) ->
    Sp = math:sqrt(VX * VX + VY * VY),
    if Sp > ?MAX_SPEED -> {VX / Sp * ?MAX_SPEED, VY / Sp * ?MAX_SPEED};
       Sp < ?MIN_SPEED andalso Sp > 0.0 ->
           {VX / Sp * ?MIN_SPEED, VY / Sp * ?MIN_SPEED};
       true -> {VX, VY}
    end.

wrap(V, Max) when V < 0    -> V + Max;
wrap(V, Max) when V >= Max -> V - Max;
wrap(V, _)                 -> V.
