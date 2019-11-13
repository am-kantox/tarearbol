import Config

config :tarearbol, persistent: false

config :cloister,
  sentry: ~w|foo_1@127.0.0.1 inexisting@127.0.0.1|a,
  consensus: 2

config :libring,
  rings: [
    # A ring which automatically changes based on Erlang cluster membership
    # Shall I node_blacklist: [:sentry] here?
    cloister: [monitor_nodes: true]
  ]

if File.exists?("config/#{Mix.env()}.exs"), do: import_config("#{Mix.env()}.exs")
