defmodule Property.Tarearbol.Test do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import StreamData

  defmacrop aib, do: quote(do: one_of([atom(:alphanumeric), integer(), binary()]))

  defmacrop leaf_list, do: quote(do: list_of(aib()))
  defmacrop leaf_map, do: quote(do: map_of(aib(), aib()))
  defmacrop leaf_keyword, do: quote(do: keyword_of(aib()))

  defmacrop leaf,
    do: quote(do: one_of([leaf_list(), leaf_map(), leaf_keyword()]))

  #  defmacrop non_leaf_list, do: quote do: list_of(leaf())
  #  defmacrop non_leaf_map, do: quote do: map_of(aib(), leaf())
  #  defmacrop non_leaf_keyword, do: quote do: keyword_of(leaf())
  #  defmacrop non_leaf,
  #    do: quote do: one_of([non_leaf_list(), non_leaf_map(), non_leaf_keyword()])
  #
  #  defmacrop maybe_leaf_list,
  #    do: quote do: list_of(one_of([leaf(), non_leaf()]))
  #  defmacrop maybe_leaf_map,
  #    do: quote do: map_of(aib(), one_of([leaf(), non_leaf()]))
  #  defmacrop maybe_leaf_keyword,
  #    do: quote do: keyword_of(one_of([leaf(), non_leaf()]))
  #  defmacrop maybe_leaf,
  #    do: quote do: one_of([maybe_leaf_list(), maybe_leaf_map(), maybe_leaf_keyword()])

  test "#ensure/2" do
    check all term <- leaf(), max_runs: 100 do
      assert {:ok, term} ==
               Tarearbol.Job.ensure(fn -> {:ok, term} end, accept_not_ok: false, attempts: 1)
    end
  end
end
