# Tarearbol

- **Lightweight task manager, allowing retries, callbacks, assurance that the task succeeded, and more**
- **Scaffold for managing many children under a `DynamicSupervisor` with a pleasure**

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

## Dynamic Workers Management

### Features

- Scaffold for the supervised `DynamicSupervisor`
- No code for managing processes required
- Implementation is as easy as 4 callbacks
- Behaviour-driven consumers
- Consistent state and callbacks on state changes (like restarting)

### [Dynamic Workers Management Examples](dynamic_workers_management.html)
