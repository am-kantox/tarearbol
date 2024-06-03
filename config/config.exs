import Config

config :tarearbol, persistent: false

config :cloister,
  sentry: :"",
  consensus: 1

if File.exists?("config/#{Mix.env()}.exs"), do: import_config("#{Mix.env()}.exs")
