-module(tasks).

-behavior(e2_application).

-export([start/0, start_tasks/1, init/0]).

start() ->
    e2_application:start_dependencies(tasks),
    application:start(tasks).

start_tasks(N) when N > 0 ->
    lists:foreach(
      fun(I) -> 
              Name = "task-" ++ integer_to_list(I),
              task_sup:start_task(Name, normal, I * 1000)
      end, lists:seq(1, N)). 

init() ->
    {ok, [{task_sup, [supervisor]}]}.
