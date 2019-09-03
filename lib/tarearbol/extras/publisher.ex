defmodule Tarearbol.Publisher do
  @moduledoc false
  use Envio.Publisher, channel: :all

  def publish(channel \\ nil, level, data)

  def publish(channel, level, data) when is_nil(channel) or not is_atom(channel),
    do: publish(:all, level, data)

  def publish(channel, level, [{k, _} | _] = data) when is_atom(k),
    do: publish(channel, level, Map.new(data))

  def publish(channel, level, data) when not is_map(data),
    do: publish(channel, level, %{body: data})

  def publish(channel, level, data) do
    data = Map.put(data, :level, level)

    broadcast(channel, data)
    unless channel == :all, do: broadcast(data)
  end
end
