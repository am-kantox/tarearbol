defmodule Tarearbol.Telemetria do
  @moduledoc false

  @default_options [use: [], apply: [level: :info]]

  @all_options :telemetria
               |> Application.get_env(:applications, [])
               |> Keyword.get(:tarearbol, [])
  @options if @all_options == true,
             do: @default_options,
             else: Keyword.merge(@default_options, @all_options)

  @use @options != [] and match?({:module, Telemetria}, Code.ensure_compiled(Telemetria))

  use Boundary

  @spec use? :: boolean()
  def use?, do: @use

  @spec maybe :: boolean()
  if @use do
    def maybe, do: use(Telemetria)
  else
    def maybe, do: false
  end

  @spec options :: keyword()
  def options, do: @options

  @spec use_options :: keyword()
  def use_options,
    do: options() |> Keyword.get(:use, [])

  @spec apply_options :: keyword()
  def apply_options,
    do: options() |> Keyword.get(:apply, [])
end
