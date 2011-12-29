-module(calc).

-export([start/0, eval/1]).

%%%-------------------------------------------------------------------
%%% Public API
%%%-------------------------------------------------------------------

start() ->
    e2_application:start_dependencies(calc),
    application:start(calc).

eval(Expr) when is_binary(Expr) ->
    eval(binary_to_list(Expr));
eval(Expr) when is_list(Expr) ->
    case parse(Expr) of
        {ok, Tree} ->
            try calc(Tree) of
                Result -> {ok, Result}
            catch
                _:E -> {error, E}
            end;
        {error, Err} ->
            {error, Err}
    end.

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

parse(Expr) ->
    case erl_scan:string(Expr) of
        {ok, Tokens, _} ->
            case calc_parser:parse(Tokens) of
                {ok, Tree} -> {ok, Tree};
                {error, {_, calc_parser, Msg}} -> {error, Msg}
            end;
        {error, Err, _} ->
            {error, Err}
    end.

calc([{'+', _}, L, R]) -> calc(L) + calc(R);
calc([{'-', _}, L, R]) -> calc(L) - calc(R);
calc([{'*', _}, L, R]) -> calc(L) * calc(R);
calc([{'/', _}, L, R]) -> calc(L) / calc(R);
calc([{'-', _}, X]) -> -calc(X);
calc({integer, _, I}) -> I;
calc({float, _, F}) -> F.
