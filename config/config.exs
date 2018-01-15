use Mix.Config

config :tarearbol, persistent: false

if File.exists?("#{Mix.env()}.exs"), do: import_config("#{Mix.env()}.exs")
