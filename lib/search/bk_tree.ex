defmodule Search.BKTree do
  @moduledoc false

  @type t :: {String.t(), any(), %{non_neg_integer() => t()}} | nil

  @spec build(Radix.tree()) :: t()
  def build(radix_tree) do
    Radix.reduce(radix_tree, nil, fn key, value, acc -> insert(acc, key, value) end)
  end

  @spec insert(t(), String.t(), any()) :: t()
  def insert(nil, term, data), do: {term, data, %{}}

  def insert({root, root_data, children}, term, data) do
    d = Search.levenshtein_distance(root, term)

    if d == 0 do
      {root, data, children}
    else
      case children do
        %{^d => child} -> {root, root_data, %{children | d => insert(child, term, data)}}
        _ -> {root, root_data, Map.put(children, d, {term, data, %{}})}
      end
    end
  end

  @spec query(t(), String.t(), non_neg_integer(), MapSet.t()) :: [{String.t(), any()}]
  def query(nil, _term, _max_dist, _tombstones), do: []

  def query({node_term, node_data, children}, term, max_dist, tombstones) do
    d = Search.levenshtein_distance(node_term, term)

    matches =
      if d <= max_dist and not MapSet.member?(tombstones, node_term),
        do: [{node_term, node_data}],
        else: []

    Enum.reduce(max(d - max_dist, 0)..min(d + max_dist, d + max_dist), matches, fn dist, acc ->
      case children do
        %{^dist => child} -> query(child, term, max_dist, tombstones) ++ acc
        _ -> acc
      end
    end)
  end
end
