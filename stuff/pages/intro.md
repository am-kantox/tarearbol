# Tarearbol

- **Scaffold for managing many children under `Tarearbol.DynamicManager` wrapping `DynamicSupervisor` with a pleasure**
- **Lightweight task manager, allowing retries, callbacks, assurance that the task succeeded, and more**
- **Lightweight scalable cron-like job scheduler `Tarearbol.Scheduler`**

## Dynamic Workers Management

### Features

- Scaffold for the supervised `DynamicSupervisor`
- No code for managing processes required
- Implementation is as easy as 4 callbacks
- Behaviour-driven consumers
- Consistent state and callbacks on state changes (like restarting)

### [Dynamic Workers Management Examples](dynamic_workers_management.html)

## Task Management

### Features

- Task supervision tree for granted
- Infinite retries until succeeded
- Async execution of a single task with retries
- Async execution of many tasks with retries
- Limited amount of retries
- Delay between retries
- Callbacks on `on_retry`, `on_success`, `on_fail`
- Configurable “success” treatment
- Task scheduling and draining, cron-like execution

### [Task Management Examples](task_management.html)

## Job Management

### Features

- Fully supported [cron syntax](https://crontab.guru/)
- Job callback with an ability to cancel and reschedule jobs
- Easy configuration via project, config, or external file
- No persistent storage required
- `Stream` with all the upcoming cron events by cron record
- `Tarearbol.Calendar.{beginning_of,end_of}/2` with full `Calendar` support

### [Job Management Examples](cron_management.html)

