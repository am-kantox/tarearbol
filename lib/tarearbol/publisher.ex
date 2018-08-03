defmodule Tarearbol.Publisher do
  use Envio.Publisher, channel: :all

  def publish(channel, what) when is_nil(channel) or not is_atom(channel),
    do: publish(:all, what)
  def publish(channel, what) when not is_map(what),
    do: publish(channel, %{result: what})
  def publish(channel, what),
    do: broadcast(channel, what)
end
