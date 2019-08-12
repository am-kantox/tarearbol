defmodule Tarearbol.Publisher do
  @moduledoc false
  use Envio.Publisher, channel: :all

  def publish(channel, value, data) when is_nil(channel) or not is_atom(channel),
    do: publish(:all, value, data)

  def publish(channel, value, data) when not is_map(data),
    do: publish(channel, value, %{result: data})

  def publish(channel, value, data) do
    data =
      data
      |> Map.put(:level, channel)
      |> Map.put(:value, value)

    broadcast(channel, data)
    unless channel == :all, do: broadcast(data)
  end
end
