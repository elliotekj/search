defmodule Search do
  @moduledoc """
  **⚡ Fast full-text search for Elixir**

  This library provides simple, fast, in-memory full-text search functionality
  for Elixir applications.

  > 👷 **Warning**
  >
  > This library is built on a solid foundation but is still under heavy
  > development.

  ## Features

  - 🧠 Memory efficient indexing of documents
  - 🔎 Exact match search
  - 🏃 Prefix search
  - 🔜 Fuzzy search
  - 🔜 Auto-suggestion engine
  - 🔢 Modern search result ranking algorithm
  - 🔀 Add and remove documents anytime

  ## Usage

  ### Creating an Index

  To create a new index, use the `new/1` function with a list of fields to be
  indexed:

      index = Search.new(fields: [:title, :content])

  ### Adding Documents

  To add a document to the index, use the `add/2` function with the index and
  the document:

      document = %{id: 1, title: "Elixir", content: "Elixir is a dynamic, functional language."}
      index = Search.add!(index, document)

  You can also add multiple documents at once:

      documents = [
        %{id: 2, title: "Phoenix", content: "Phoenix is a web framework for Elixir."},
        %{id: 3, title: "Nerves", content: "Nerves is a framework for embedded systems."}
      ]
      index = Search.add!(index, documents)

  ### Removing Documents

  To remove a document from the index, use the `remove/2` function with the
  index and the document:

      index = Search.remove!(index, document)

  You can also remove multiple documents at once:

      index = Search.remove!(index, documents)

  ### Searching

  To search the index, use the `search/3` function with the index and the query
  string:

      Search.search(index, "Elixir")
      [
        %{
          id: 1,
          matches: %{"elixir" => [:title, :content]},
          fields: %{},
          terms: ["elixir"],
          score: 2.194907312448878
        },
        %{
          id: 2,
          matches: %{"elixir" => [:content]},
          fields: %{},
          terms: ["elixir"],
          score: 0.6962007371655166
        }
      ]

  ## Internals

  The library uses a Radix tree for efficient indexing and retrieval of terms.
  It also implements the BM25 algorithm for relevance scoring.
  """
  use TypedStruct

  typedstruct module: Index do
    # Keyword list of the indexed fields and their field IDs
    field :fields, Keyword.t()
    # Length of each field keyed by short id
    field :field_lengths, map(), default: %{}
    # Average length of each field keyed by field id
    field :avg_field_lengths, map(), default: %{}
    # The fields that are returned with search results
    field :return_fields, list(), default: []
    # Field data returned with search results
    field :return_field_data, map(), default: %{}
    # Short IDs mapped to document IDs
    field :short_ids, map(), default: %{}
    # Document IDs mapped to short IDs
    field :ids, map(), default: %{}
    # The next short ID to use
    field :next_id, integer(), default: 1
    # The number of documents in the index
    field :document_count, integer(), default: 0
    # Radix Tree index
    field :tree, Radix.tree(), default: Radix.new()
    # Document hashes
    field :hashes, map(), default: %{}
  end

  @doc """
  Creates a new search index.

  ## Parameters

    - opts: A keyword list of options.
      - `fields` - A list of fields to be indexed.
      - `return_field_data` - (Optional) A list of fields to be returned with search results.

  ## Returns

    - A new `%Index{}` struct.

  ## Examples

      iex> index = Search.new(fields: [:title, :content])
  """
  @spec new(Keyword.t()) :: Search.Index.t()
  def new(opts) do
    fields = Keyword.fetch!(opts, :fields) |> Enum.with_index()
    return_fields = Keyword.get(opts, :return_field_data, [])

    %Index{
      fields: fields,
      return_fields: return_fields
    }
  end

  @doc """
  Adds a document or a list of documents to the index.

  ## Parameters

    - `index`: The current index state.
    - `document`: A map representing a single document or a list of such maps.

  ## Returns

    - The updated index with the new document(s) added.

  ## Examples

      iex> index = Search.new(fields: [:title, :content])
      iex> document = %{id: 1, title: "Elixir", content: "Elixir is a dynamic, functional language."}
      iex> {:ok, index} = Search.add(index, document)
      iex> documents = [
      ...>   %{id: 2, title: "Phoenix", content: "Phoenix is a web framework for Elixir."},
      ...>   %{id: 3, title: "Nerves", content: "Nerves is a framework for embedded systems."}
      ...> ]
      iex> {:ok, index} = Search.add(index, documents)
  """
  @spec add(Index.t(), map() | list(map())) :: {:ok, Index.t()} | {:error, String.t()}
  def add({:error, _} = error, _documents), do: error
  def add({:ok, index}, documents), do: add(index, documents)

  def add(index, []), do: {:ok, index}

  def add(index, [doc | documents]), do: add(index, doc) |> add(documents)

  def add(index, document) do
    try do
      {:ok, add!(index, document)}
    rescue
      e -> {:error, e.message}
    end
  end

  @doc """
  Adds a document or a list of documents to the index like `add/2`, but raises
  if an error occurs.
  """
  @spec add!(Index.t(), map() | list(map())) :: Index.t()
  def add!(index, []), do: index

  def add!(index, [doc | documents]), do: add!(index, doc) |> add!(documents)

  def add!(index, document) do
    id = get_doc_id(document)

    if Map.has_key?(index.ids, id) do
      raise Search.DocumentExistsError
    end

    {index, short_id} = add_doc_id(index, document)
    return_field_data = get_return_field_data(index, document)
    hashes = Map.put(index.hashes, short_id, :erlang.phash2(document))

    index = %{
      index
      | return_field_data: Map.put(index.return_field_data, short_id, return_field_data),
        hashes: hashes
    }

    Enum.reduce(index.fields, index, fn {f, field_id}, acc ->
      value = Map.get(document, f)
      tokens = tokenize(value)
      unique_term_count = tokens |> Enum.uniq() |> length()

      index = add_field_length(acc, short_id, field_id, unique_term_count)

      Enum.reduce(tokens, index, fn t, acc ->
        processed_term = process_term(t)
        {_, term_data} = Radix.get(acc.tree, processed_term, {processed_term, %{}})
        field_index = Map.get(term_data, field_id, %{})
        term_count = Map.get(field_index, short_id, 0) + 1
        field_index = Map.put(field_index, short_id, term_count)
        term_data = Map.put(term_data, field_id, field_index)
        %{acc | tree: Radix.put(acc.tree, processed_term, term_data)}
      end)
    end)
  end

  @doc """
  Removes a document or a list of documents from the index. The document(s) must be unchanged.

  ## Parameters

    - `index`: The current index state.
    - `document`: A map representing a single document or a list of such maps to be removed.

  ## Returns

    - The updated index with the document(s) removed.

  ## Examples

      iex> index = Search.new(fields: [:title, :content])
      iex> document = %{id: 1, title: "Elixir", content: "Elixir is a dynamic, functional language."}
      iex> index = Search.add!(index, document)
      iex> {:ok, index} = Search.remove(index, document)
      iex> documents = [
      ...>   %{id: 2, title: "Phoenix", content: "Phoenix is a web framework for Elixir."},
      ...>   %{id: 3, title: "Nerves", content: "Nerves is a framework for embedded systems."}
      ...> ]
      iex> index = Search.add!(index, documents)
      iex> {:ok, index} = Search.remove(index, documents)
  """
  @spec remove(Index.t(), map() | list(map())) :: {:ok, Index.t()} | {:error, String.t()}
  def remove({:error, _} = error, _documents), do: error
  def remove({:ok, index}, documents), do: remove(index, documents)

  def remove(index, []), do: {:ok, index}

  def remove(index, [doc | documents]), do: remove(index, doc) |> remove(documents)

  def remove(index, document) do
    try do
      {:ok, remove!(index, document)}
    rescue
      e -> {:error, e.message}
    end
  end

  @doc """
  Removes a document or a list of documents from the index like `remove/2`, but raises
  if an error occurs.
  """
  @spec remove!(Index.t(), map() | list(map())) :: Index.t()
  def remove!(index, []), do: index

  def remove!(index, [document | documents]), do: remove!(index, document) |> remove!(documents)

  def remove!(index, document) when is_map(document) do
    id = get_doc_id(document)

    if not Map.has_key?(index.ids, id) do
      raise Search.DocumentNotExistsError
    end

    short_id = Map.get(index.ids, id)

    if Map.get(index.hashes, short_id) != :erlang.phash2(document) do
      raise Search.DocumentMutatedError
    end

    index =
      Enum.reduce(index.fields, index, fn {f, field_id}, acc ->
        value = Map.get(document, f)
        tokens = tokenize(value)
        unique_term_count = tokens |> Enum.uniq() |> length()

        index = remove_field_length(acc, field_id, unique_term_count)

        Enum.reduce(tokens, index, fn t, acc ->
          processed_term = process_term(t)
          {_, term_data} = Radix.get(acc.tree, processed_term, {processed_term, %{}})
          field_index = Map.get(term_data, field_id, %{}) |> Map.delete(short_id)

          cond do
            field_index == %{} && map_size(term_data) == 1 ->
              %{acc | tree: Radix.delete(acc.tree, processed_term)}

            field_index == %{} ->
              term_data = Map.delete(term_data, field_id)
              %{acc | tree: Radix.put(acc.tree, processed_term, term_data)}

            true ->
              term_data = Map.put(term_data, field_id, field_index)
              %{acc | tree: Radix.put(acc.tree, processed_term, term_data)}
          end
        end)
      end)

    %{
      index
      | return_field_data: Map.delete(index.return_field_data, short_id),
        short_ids: Map.delete(index.short_ids, short_id),
        ids: Map.delete(index.ids, id),
        document_count: index.document_count - 1,
        field_lengths: Map.delete(index.field_lengths, short_id),
        hashes: Map.delete(index.hashes, short_id)
    }
  end

  @doc """
  Searches the index for documents matching the given query string.

  ## Parameters

    - `index`: The current index state.
    - `query_string`: The search query string.
    - `opts`: The search options.
      - `prefix?`: Whether to perform a prefix search. Defaults to `false`.
      - `fuzzy?`: Whether to perform a fuzzy search. Defaults to `false`.
      - `fuzziness`: The fuzziness to use for the fuzzy search; i.e. the maximum edit distance between terms being compared. Defaults to `2`.
      - `weights`: The weights to use for the search. Defaults to `[prefix: 0.375, fuzzy: 0.45]`.

  ## Returns

    - A list of maps representing the search results, sorted by relevance score in descending order. Each map contains:
      - `id` - The document ID.
      - `fields` - The fields returned with the search results.
      - `score` - The relevance score of the document.
      - `terms` - The terms that matched in the document.
      - `matches` - The fields in which the terms matched.

  ## Examples

      iex> index = Search.new(fields: [:title, :content])
      iex> document = %{id: 1, title: "Elixir", content: "Elixir is a dynamic, functional language."}
      iex> index = Search.add!(index, document)
      iex> Search.search(index, "Elixir")
      [
        %{
          id: 1,
          fields: %{},
          score: 0.8630462173553426,
          terms: ["elixir"],
          matches: %{"elixir" => [:title, :content]}
        }
      ]
      iex> Search.search(index, "Eli", prefix?: true)
      [
        %{
          id: 1,
          fields: %{},
          score: 0.28142811435500303,
          terms: ["elixir"],
          matches: %{"elixir" => [:title, :content]}
        }
      ]
  """
  @spec search(Index.t(), String.t(), Keyword.t()) :: [map()]
  def search(index, query_string, opts \\ []) do
    prefix_search? = Keyword.get(opts, :prefix?, false)
    fuzzy_search? = Keyword.get(opts, :fuzzy?, false)
    weights = Keyword.get(opts, :weights, [])
    prefix_weight = Keyword.get(weights, :prefix, 0.375)
    fuzzy_weight = Keyword.get(weights, :fuzzy, 0.45)
    fuzziness = Keyword.get(opts, :fuzziness, 2)

    terms = tokenize(query_string) |> Enum.map(&process_term/1)
    query_terms = Enum.map(terms, &%{term: &1})

    query_exact_terms(index, query_terms)
    |> query_prefixed_terms(prefix_search?, index, query_terms, prefix_weight)
    |> query_fuzzy_terms(fuzzy_search?, index, query_terms, fuzzy_weight, fuzziness)
    |> Enum.reduce(%{}, fn {{short_id, term}, result}, acc ->
      existing = Map.get(acc, short_id, %{score: 0, terms: [], matches: %{}})
      terms = Enum.uniq([term | existing.terms])

      term_matches =
        Map.get(existing.matches, term, [])
        |> Kernel.++(result.matches)
        |> Enum.uniq()

      matches = Map.merge(existing.matches, %{term => term_matches})

      Map.put(acc, short_id, %{
        existing
        | score: existing.score + result.score,
          terms: terms,
          matches: matches
      })
    end)
    |> Enum.map(fn {short_id, result} ->
      doc_id = Map.get(index.short_ids, short_id)
      fields = Map.get(index.return_field_data, short_id, %{})
      result |> Map.put(:id, doc_id) |> Map.put(:fields, fields)
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  defp query_exact_terms(index, query_terms, acc \\ %{}) do
    Enum.reduce(query_terms, acc, fn query_term, acc ->
      {term, term_data} = Radix.get(index.tree, query_term.term, {query_term.term, %{}})
      query_term(acc, index, term, term_data, 1)
    end)
  end

  defp query_prefixed_terms(acc, false, _index, _query_terms, _prefix_weight), do: acc

  defp query_prefixed_terms(acc, true, index, query_terms, prefix_weight) do
    Enum.reduce(query_terms, acc, fn query_term, acc ->
      Radix.more(index.tree, query_term.term, exclude: true)
      |> Enum.reduce(acc, fn {term, term_data}, acc ->
        term_length = String.length(term)
        distance = term_length - String.length(query_term.term)
        weight = prefix_weight * term_length / (term_length + 0.3 * distance)
        query_term(acc, index, term, term_data, weight)
      end)
    end)
  end

  defp query_fuzzy_terms(acc, false, _index, _query_terms, _fuzzy_weight, _fuzziness), do: acc

  defp query_fuzzy_terms(acc, true, index, query_terms, fuzzy_weight, fuzziness) do
    opts = [fuzzy_weight: fuzzy_weight, fuzziness: fuzziness]
    Enum.reduce(query_terms, acc, &query_fuzzy_term(&2, index, &1, opts))
  end

  defp query_fuzzy_term(acc, index, query_term, opts) do
    term_length = String.length(query_term.term)
    min_length = term_length - opts[:fuzziness]
    max_length = term_length + opts[:fuzziness]
    weight = opts[:fuzzy_weight] * term_length / (term_length + opts[:fuzziness])

    opts =
      Keyword.merge(opts,
        term_length: term_length,
        min_length: min_length,
        max_length: max_length,
        weight: weight
      )

    Radix.walk(index.tree, acc, &evaluate_nodes(&1, &2, index, query_term, opts))
  end

  defp evaluate_nodes(acc, {_bit, _left, _right}, _index, _query_term, _opts), do: acc

  defp evaluate_nodes(acc, leaf, index, query_term, opts) do
    Enum.reduce(leaf, acc, &evaluate_leaf(&1, &2, index, query_term, opts))
  end

  defp evaluate_leaf({term, term_data}, acc, index, query_term, opts) do
    min_length = Keyword.get(opts, :min_length)
    max_length = Keyword.get(opts, :max_length)
    fuzziness = Keyword.get(opts, :fuzziness)

    with true <- String.length(term) >= min_length and String.length(term) <= max_length,
         true <- Leven.distance(query_term.term, term) <= fuzziness do
      weight = Keyword.get(opts, :weight)
      query_term(acc, index, term, term_data, weight)
    else
      _ -> acc
    end
  end

  defp query_term(acc, index, term, term_data, term_weight) do
    Enum.reduce(index.fields, acc, fn {field, field_id}, acc ->
      term_freqs = Map.get(term_data, field_id, %{})
      matching_fields = map_size(term_freqs)
      avg_field_length = index.avg_field_lengths[field_id]

      Enum.reduce(term_freqs, acc, fn {short_id, term_freq}, acc ->
        result = Map.get(acc, {short_id, term}, %{score: 0, matches: []})

        if Enum.member?(result.matches, field) do
          # The term has already been matched in this field by a preceeding
          # search type. Search is done from highest to lowest precision, so if
          # the term has already been matched in this field, we skip.
          acc
        else
          field_length = Enum.at(index.field_lengths[short_id], field_id)

          raw_score =
            calc_bm25(
              term_freq,
              matching_fields,
              index.document_count,
              field_length,
              avg_field_length
            )

          weighted_score = raw_score * term_weight
          score = result.score + weighted_score
          matches = result.matches |> Kernel.++([field]) |> Enum.uniq()

          Map.put(acc, {short_id, term}, %{result | score: score, matches: matches})
        end
      end)
    end)
  end

  defp get_doc_id(document) do
    case Map.get(document, :id) || Map.get(document, "id") do
      nil -> raise Search.DocumentMissingIdError
      id -> id
    end
  end

  defp add_doc_id(index, document) do
    short_id = index.next_id
    document_id = get_doc_id(document)
    short_ids = Map.put(index.short_ids, short_id, document_id)
    ids = Map.put(index.ids, document_id, short_id)

    index = %{
      index
      | ids: ids,
        short_ids: short_ids,
        next_id: index.next_id + 1,
        document_count: index.document_count + 1
    }

    {index, short_id}
  end

  defp get_return_field_data(index, document) do
    Enum.reduce(index.return_fields, %{}, fn f, acc ->
      value = Map.get(document, f)
      Map.put(acc, f, value)
    end)
  end

  defp tokenize(value) when is_binary(value) do
    Regex.split(~r/[\n\r\p{Z}\p{P}]/, value, trim: true)
  end

  defp tokenize(value) do
    if String.Chars.impl_for(value) do
      to_string(value) |> tokenize()
    else
      raise Search.DocumentFieldNotString
    end
  end

  defp process_term(term), do: String.downcase(term)

  defp add_field_length(index, short_id, field_id, length) do
    count = index.document_count - 1
    field_lengths = Map.get(index.field_lengths, short_id, []) |> Kernel.++([length])
    avg_length = Map.get(index.avg_field_lengths, field_id, 0)
    total_length = avg_length * count + length
    avg_lengths = Map.put(index.avg_field_lengths, field_id, total_length / (count + 1))

    %{
      index
      | field_lengths: Map.put(index.field_lengths, short_id, field_lengths),
        avg_field_lengths: avg_lengths
    }
  end

  defp remove_field_length(%Index{document_count: 1} = index, _field_id, _length) do
    %{index | avg_field_lengths: %{}}
  end

  defp remove_field_length(%Index{document_count: count} = index, field_id, length) do
    avg_length = Map.get(index.avg_field_lengths, field_id, 0)
    total_length = avg_length * count - length
    avg_lengths = Map.put(index.avg_field_lengths, field_id, total_length / (count - 1))

    %{index | avg_field_lengths: avg_lengths}
  end

  defp calc_bm25(term_freq, matching_count, total_count, field_length, avg_field_length) do
    k = 1.2
    b = 0.7
    d = 0.5

    inv_doc_freq = :math.log(1 + (total_count - matching_count + 0.5) / (matching_count + 0.5))

    inv_doc_freq *
      (d + term_freq * (k + 1) / (term_freq + k * (1 - b + b * field_length / avg_field_length)))
  end
end
