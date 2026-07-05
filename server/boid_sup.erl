%%% boid_sup.erl — simple_one_for_one supervisor.
%%% Kill any boid (flock:chaos/0) and it is reborn instantly.
-module(boid_sup).
-behaviour(supervisor).

-export([start_link/0, spawn_boid/1]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

spawn_boid(Id) ->
    supervisor:start_child(?MODULE, [Id]).

init([]) ->
    SupFlags = #{strategy => simple_one_for_one,
                 intensity => 100,     % tolerate a storm of crashes
                 period => 1},
    Child = #{id => boid,
              start => {boid, start_link, []},
              restart => permanent,
              shutdown => brutal_kill,
              type => worker},
    {ok, {SupFlags, [Child]}}.
