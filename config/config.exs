import Config

config :tarearbol, persistent: false

config :cloister,
  sentry: ~w|tarearbol_1@127.0.0.1 inexisting@127.0.0.1|a,
  consensus: 1

if File.exists?("config/#{Mix.env()}.exs"), do: import_config("#{Mix.env()}.exs")
