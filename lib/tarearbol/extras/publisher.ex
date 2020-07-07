defmodule Tarearbol.Publisher do
  @moduledoc false

  if Application.get_env(:tarearbol, :notify_broadcast, true) and
       match?({:module, Envio.Publisher}, Code.ensure_compiled(Envio.Publisher)) do
    use Envio.Publisher

    @spec publish(channel :: atom(), level :: atom(), data :: map()) :: :ok
    def publish(channel \\ nil, level, data)

    def publish(channel, level, data) when is_nil(channel) or not is_atom(channel),
      do: publish(:tarearbol, level, data)

    def publish(channel, level, data),
      do: broadcast(channel, Map.put(data, :level, level))
  else
    def publish(_, _, _), do: :ok
  end
end
