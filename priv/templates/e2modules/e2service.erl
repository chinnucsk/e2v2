-module({{module}}).

-behavior(e2_service).

-export([start_link/0, ping/0]).

-export([init/1, handle_msg/3]).

-record(state, {}).

%%%===================================================================
%%% Public API
%%%===================================================================

start_link() ->
    e2_service:start_link(?MODULE, [], [registered]).

ping() ->
    e2_service:start_link(?MODULE, ping).

%%%===================================================================
%%% Service callbacks
%%%===================================================================

init([]) ->
    {ok, #state{}}.

handle_msg(ping, _From, State) ->
    {reply, pong, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
