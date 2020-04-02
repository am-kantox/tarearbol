import Config

config :cloister,
  sentry: ~w|foo_1@127.0.0.1 inexisting@127.0.0.1|a,
  consensus: 1

# config :envio, :backends, %{
#   Envio.Slack => %{
#     {Tarearbol.Publisher, :info} => [
#       hook_url: {:system, "SLACK_ENVIO_HOOK_URL"}
#     ]
#   }
# }
