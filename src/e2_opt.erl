-module(e2_opt).

-export([validate/2, validate/3, value/2]).

-define(NO_DEFAULT, '$e2_opt_nodefault').

-record(schema, {implicit, constraints}).
-record(constraint,
        {values,
         type,
         min,
         max,
         pattern,
         validator,
         implicit=false,
         default=?NO_DEFAULT}).

-define(is_type(T), (T == int orelse
                     T == float orelse
                     T == string orelse
                     T == number orelse
                     is_function(T))).

%%%===================================================================
%%% API
%%%===================================================================

validate(Options, Schema) ->
    validate(Options, compile_schema(Schema), dict:new()).

validate([], #schema{}=Schema, Opts0) ->
    apply_missing(Schema, Opts0);
validate([Opt|Rest], #schema{}=Schema, Opts0) ->
    validate(Rest, Schema, apply_opt(Opt, Schema, Opts0));
validate(MoreOptions, Schema, Opts0) ->
    validate(MoreOptions, compile_schema(Schema), Opts0).

value(Name, Opts) -> dict:fetch(Name, Opts).

compile_schema(Schema) ->
    Constraints = [compile_constraint(C) || C <- Schema],
    #schema{implicit=index_implicit(Constraints), constraints=Constraints}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

compile_constraint(Name) when is_atom(Name) ->
    {Name, #constraint{}};
compile_constraint({Name, Opts}) ->
    {Name, apply_constraint_options(Opts, #constraint{})}.

index_implicit(Constraints) ->
    index_implicit(Constraints, dict:new()).

index_implicit([], Imp) -> Imp;
index_implicit([{_, #constraint{implicit=false}}|Rest], Imp) ->
    index_implicit(Rest, Imp);
index_implicit([{Name, #constraint{implicit=true, values=undefined}}|_], _) ->
    error({values_required, Name});
index_implicit([{Name, #constraint{implicit=true, values=Vals}}|Rest], Imp) ->
    index_implicit(Rest, index_implicit_vals(Name, Vals, Imp)).

index_implicit_vals(_, [], Imp) -> Imp;
index_implicit_vals(Name, [Val|Rest], Imp) ->
    case dict:find(Val, Imp) of
        {ok, _} -> error({duplicate_implicit_value, Val});
        error -> index_implicit_vals(Name, Rest, dict:store(Val, Name, Imp))
    end.

-define(constraint_val(Field, Val, C), C#constraint{Field=Val}).

apply_constraint_options([], C) -> C;
apply_constraint_options([{values, Values}|Rest], C) when is_list(Values) ->
    apply_constraint_options(Rest, ?constraint_val(values, Values, C));
apply_constraint_options([{type, Type}|Rest], C) when ?is_type(Type) ->
    apply_constraint_options(Rest, ?constraint_val(type, Type, C));
apply_constraint_options([{min, Min}|Rest], C) ->
    apply_constraint_options(Rest, ?constraint_val(min, Min, C));
apply_constraint_options([{max, Max}|Rest], C) ->
    apply_constraint_options(Rest, ?constraint_val(max, Max, C));
apply_constraint_options([{pattern, Pattern}|Rest], C) ->
    apply_constraint_options(
      Rest, ?constraint_val(pattern, compile_pattern(Pattern), C));
apply_constraint_options([{validator, F}|Rest], C) when is_function(F) ->
    apply_constraint_options(
      Rest, ?constraint_val(validator, check_validator(F), C));
apply_constraint_options([{default, Default}|Rest], C) ->
    apply_constraint_options(Rest, ?constraint_val(default, Default, C));
apply_constraint_options([implicit|Rest], C) ->
    apply_constraint_options(Rest, ?constraint_val(implicit, true, C));
apply_constraint_options([{Name, _}|_], _) ->
    error({badarg, Name});
apply_constraint_options([Other|_], _) ->
    error({badarg, Other}).

compile_pattern(Pattern) ->
    case re:compile(Pattern) of
        {ok, Re} -> Re;
        {error, _} -> error({badarg, pattern})
    end.

check_validator(F) ->
    case erlang:fun_info(F, arity) of
        {arity, 1} -> F;
        {arity, _} -> error({badarg, validator})
    end.

apply_opt(Opt, Schema, Opts) ->
    {Name, Value} = validate_opt(Opt, Schema),
    case dict:find(Name, Opts) of
        {ok, _} -> error({duplicate, Name});
        error -> dict:store(Name, Value, Opts)
    end.

validate_opt({Name, Value}, Schema) ->
    case find_constraint(Name, Schema) of
        {ok, Constraint} ->
            case check_value(Value, Constraint) of
                ok -> {Name, Value};
                error -> error({value, Name})
            end;
        error -> error({option, Name})
    end;
validate_opt(Option, Schema) ->
    case implicit_option(Option, Schema) of
        {ok, Name} -> {Name, Option};
        error ->
            validate_opt({Option, true}, Schema)
    end.

find_constraint(Name, #schema{constraints=Constraints}) ->
    case lists:keyfind(Name, 1, Constraints) of
        {Name, Constraint} -> {ok, Constraint};
        false -> error
    end.

implicit_option(Value, #schema{implicit=Implicit}) ->
    case dict:find(Value, Implicit) of
        {ok, Name} -> {ok, Name};
        error -> error
    end.

check_value(Val, Constraint) ->
    apply_checks(Val, Constraint,
                 [fun check_enum/2,
                  fun check_type/2,
                  fun check_range/2,
                  fun check_pattern/2,
                  fun check_validator/2]).

apply_checks(_Val, _Constraint, []) -> ok;
apply_checks(Val, Constraint, [Check|Rest]) ->
    case Check(Val, Constraint) of
        ok -> apply_checks(Val, Constraint, Rest);
        error -> error
    end.

check_enum(_Val, #constraint{values=undefined}) -> ok;
check_enum(Val, #constraint{values=Values}) ->
    case lists:member(Val, Values) of
        true -> ok;
        false -> error
    end.

-define(is_iolist(T),
        try erlang:iolist_size(Val) of
            _ -> true
        catch
            error:badarg -> false
        end).

check_type(_Val, #constraint{type=undefined}) -> ok;
check_type(Val, #constraint{type=int}) when is_integer(Val) -> ok;
check_type(Val, #constraint{type=float}) when is_float(Val) -> ok;
check_type(Val, #constraint{type=number}) when is_number(Val) -> ok;
check_type(Val, #constraint{type=string}) ->
    case ?is_iolist(Val) of
        true -> ok;
        false -> error
    end;
check_type(_, _) -> error.

check_range(_Val, #constraint{min=undefined, max=undefined}) -> ok;
check_range(Val, #constraint{min=undefined, max=Max}) when Val =< Max -> ok;
check_range(Val, #constraint{min=Min, max=undefined}) when Val >= Min -> ok;
check_range(Val, #constraint{min=Min, max=Max}) when Val =< Max,
                                                     Val >= Min-> ok;
check_range(_, _) -> error.

check_pattern(_Val, #constraint{pattern=undefined}) -> ok;
check_pattern(Val, #constraint{pattern=Regex}) ->
    case re:run(Val, Regex, [{capture, none}]) of
        match -> ok;
        nomatch -> error
    end.

check_validator(_Val, #constraint{validator=undefined}) -> ok;
check_validator(Val, #constraint{validator=Validate}) ->
    case Validate(Val) of
        ok -> ok;
        error -> error;
        Other -> error({validator_result, Other})
    end.

apply_missing(#schema{constraints=Constraints}, Opts0) ->
    lists:foldl(fun apply_default/2, Opts0, Constraints).

apply_default({Name, #constraint{default=Default}}, Opts) ->
    case dict:find(Name, Opts) of
        {ok, _} -> Opts;
        error ->
            case Default of
                ?NO_DEFAULT -> error({required, Name});
                _ -> dict:store(Name, Default, Opts)
            end
    end.
