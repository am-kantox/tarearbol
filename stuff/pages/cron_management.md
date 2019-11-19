# Cron Management

## Intro

`Tarearbol` provides a simple but robust support of cron-like jobs scheduling. The approach is to spawn a process for each job to be completed under `Tarearbol.DynamicManager` supervision. `Tarearbol` application _does not_ start the `Tarearbol.Scheduler` automatically, the target application must include it into it’s supervision tree explicitly.

Jobs description are loaded upon application start from one of the following locations:

- `project` section of the `Mix.Project`, key `:tarearbol`, subkey `:jobs`
- `config` entry in `Config` script, key `:tarearbol`, subkey `:jobs`
- `.tarearbol.exs` file in the root folder of the target project (the path to the file might be configured in `project` section  of the `Mix.Project`, key `:tarearbol`, subkey `:jobs_file`)

`Tarearbol.Scheduler` understands `cron` format. It exports three handy methods from `Tarearbol.Crontab` module, `Tarearbol.Crontab.next/3`, `Tarearbol.Crontab.next_as_stream/3` and `Tarearbol.Crontab.next_as_list/3`. The first might be used to get the timestamp of the _next_ event by cron record, the second to greedy evaluate all the next events for the year and the last one to return a `Stream` lazily evaluating next events.

---

## Job Management

`Tarearbol.Scheduler` was created mostly for the single-node application, but it might be easily extended to manage jobs on several nodes.

Upon start, it loads jobs schedules and spawns processes for each, managed by `Tarearbol.DynamicManager`. Each job must return on of the following three outcomes.

- `{:ok, any()}` to normally return the result to be stored as last job execution result in the state of `Tarearbol.DynamicSupervisor` and reschedule the job to the next event
- `:halt` to prevent further job executions and remove it from the list of scheduled jobs
- `{{:reschedule, binary()}, any()}` to reschedule the job with new cron record, given as the second parameter of the first tuple.

---

## Extra Sugar

`Tarearbol.Calendar` exposes two functions stolen from _Rails_:

- `Tarearbol.Calendar.beginning_of/2` returns the beginning of the period including the timestamp given as an argument
- `Tarearbol.Calendar.end_of/2` returns the end of the period including the timestamp.