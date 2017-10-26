defmodule Tarearbol.Utils do
  @moduledoc """
  Set of utilities used in `Tarearbol`. It currently includes human-to-machine
    interval conversions and options extractor.
  """

  @type interval :: (Integer.t | Float.t |
                     :none | :tiny | :medium | :regular |
                     :timeout | :infinity | :random)

  @doc """
  Converts a human representation of time interval to the one
    understandable by a computer. The conversion rules are:

  - `integer` → amount to be used as is (milliseconds for `delay`, number for attempts);
  - `float` → amount of thousands, rounded (seconds for `delay`, thousands for attempts);
  - `:none` → `0`;
  - `:tiny` → `10`;
  - `:medium` → `100`;
  - `:infinity` → `-1`, `:attempts` only.
  """
  @spec interval(Interval.t, List.t) :: Integer.t
  def interval(input, opts \\ []) do
    case input do
      0 -> -1
      0.0 -> -1
      msec when is_integer(msec) and msec > 0 -> msec
      sec when is_float(sec) and sec > 0 -> round(1_000 * sec)
      :tiny -> 10
      :medium -> 100
      :regular -> 1_000
      :timeout -> 5_000
      :infinity -> opts[:value] || -1
      :random -> :rand.uniform((opts[:value] || 5_000) + 1) - 1
      _ -> 0
    end
  end

  @doc """
  Adds an interval to the given `DateTime` instance (or to
    `DateTime.utc_now` if none given, returning the `DateTime` instance.
  """
  @spec add_interval(Interval.t, DateTime.t | nil) :: DateTime.t
  def add_interval(input, to \\ nil)
  def add_interval(input, nil), do: add_interval(input, DateTime.utc_now)
  def add_interval(input, %DateTime{} = to) do
    to
    |> DateTime.to_unix(:milliseconds)
    |> Kernel.+(interval(input))
    |> DateTime.from_unix!(:milliseconds)
  end

  #############################################################################

  @default_opts [
    attempts: 0, delay: 0, timeout: 5_000, raise: false, accept_not_ok: true,
    on_success: nil, on_retry: :debug, on_fail: :warn]

  @doc false
  @spec opts(Keyword.t) :: Keyword.t
  def opts(opts),
    do: Keyword.merge(Application.get_env(:tarearbol, :job_options, @default_opts), opts)

  @doc false
  @spec extract_opts(Keyword.t, Atom.t | List.t, any) :: Keyword.t
  def extract_opts(opts, name, default \\ nil)
  def extract_opts(opts, name, default) when is_atom(name) do
    opts = opts(opts)
    {Keyword.get(opts, name, default), Keyword.delete(opts, name)}
  end
  def extract_opts(opts, names, default) when is_list(names) and is_nil(default),
    do: Keyword.split(opts(opts), names)

  #############################################################################

  def cron_to_time(at) when is_binary(at), do: raise "NYI: #{inspect at}"

  # defp decronify(<<"*/" :: binary, rest :: binary>>, min, max) do
  # defp decronify(<<"*/" :: binary, rest :: binary>>, min, max) do
  #   every = String.to_integer(rest)
  #   "*"
  #   |> decronify(min, max)
  #   |> Enum.with_index
  #   |> Enum.filter(fn {_, idx} -> Integer.mod(idx, every) == 0 end)
  #   |> Enum.map(fn {value, _} -> value end)
  # end
  # defp decronify("*", min, max), do: Enum.to_list(min..max)

end
