import Config

config :tarearbol, persistent: false

config :libring,
  rings: [
    cloister: [monitor_nodes: true]
  ]

if File.exists?("config/#{Mix.env()}.exs"), do: import_config("#{Mix.env()}.exs")
