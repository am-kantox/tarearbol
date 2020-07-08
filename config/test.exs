import Config

config :cloister,
  sentry: ~w|tarearbol_1@127.0.0.1 inexisting@127.0.0.1|a,
  consensus: 1

config :telemetria, applications: [tarearbol: true]
