defmodule SearchTest do
  @moduledoc false
  use ExUnit.Case, async: true
  doctest Search

  @documents [
    %{id: 100, title: "Elixir", content: "Elixir is a dynamic, functional language.", tag: "lang"},
    %{id: 101, title: "Phoenix", content: "Phoenix is a web framework for Elixir.", tag: "framework"},
    %{id: 102, title: "Nerves", content: "Nerves is a framework for embedded systems.", tag: "framework"}
  ]

  @opts [fields: [:title, :content]]

  defp build_index(docs \\ @documents, opts \\ @opts) do
    Search.new(opts) |> Search.add!(docs)
  end

  defp ids(results), do: Enum.map(results, & &1.id)
  defp scores(results), do: Enum.map(results, & &1.score)

  # ---------------------------------------------------------------------------
  # new/1
  # ---------------------------------------------------------------------------
  describe "new/1" do
    test "raises KeyError if fields is missing" do
      assert_raise KeyError, fn -> Search.new(return_field_data: [:title]) end
    end

    test "creates an empty index that returns no results" do
      index = Search.new(fields: [:title])
      assert Search.search(index, "anything") == []
    end
  end

  # ---------------------------------------------------------------------------
  # add/2 and add!/2
  # ---------------------------------------------------------------------------
  describe "add!/2" do
    test "added document is searchable" do
      index = Search.new(@opts) |> Search.add!(List.first(@documents))
      assert [%{id: 100}] = Search.search(index, "Elixir")
    end

    test "multiple documents are all searchable" do
      index = build_index()
      assert length(Search.search(index, "framework")) == 2
    end

    test "missing indexed field does not error" do
      index = Search.new(fields: [:title, :text]) |> Search.add!(%{id: 1, text: "hello"})
      assert [%{id: 1}] = Search.search(index, "hello")
    end

    test "raises DocumentMissingIdError without id" do
      assert_raise Search.DocumentMissingIdError, fn ->
        Search.new(@opts) |> Search.add!(%{title: "no id"})
      end
    end

    test "raises DocumentExistsError on duplicate id" do
      assert_raise Search.DocumentExistsError, fn ->
        Search.new(@opts)
        |> Search.add!(%{id: 1, title: "a"})
        |> Search.add!(%{id: 1, title: "b"})
      end
    end

    test "stringifies fields that implement String.Chars" do
      index = Search.new(fields: [:title, :text]) |> Search.add!(%{id: 1, title: 42, text: "x"})
      assert [%{id: 1}] = Search.search(index, "42")
    end

    test "raises DocumentFieldNotString for non-stringable fields" do
      assert_raise Search.DocumentFieldNotString, fn ->
        Search.new(fields: [:data]) |> Search.add!(%{id: 1, data: %{nested: true}})
      end
    end
  end

  describe "add/2" do
    test "returns {:ok, index} on success" do
      {:ok, index} = Search.new(@opts) |> Search.add(List.first(@documents))
      assert [%{id: 100}] = Search.search(index, "Elixir")
    end

    test "adds a list of documents" do
      {:ok, index} = Search.new(@opts) |> Search.add(@documents)
      assert length(Search.search(index, "framework")) == 2
    end

    test "returns {:error, _} when id is missing" do
      assert {:error, _} = Search.new(@opts) |> Search.add(%{title: "no id"})
    end

    test "error on nth document stops and returns error" do
      assert {:error, _} =
               Search.new(@opts) |> Search.add([%{id: 1, title: "ok"}, %{title: "no id"}])
    end
  end

  # ---------------------------------------------------------------------------
  # remove/2 and remove!/2
  # ---------------------------------------------------------------------------
  describe "remove!/2" do
    test "removed document is no longer searchable" do
      doc = List.first(@documents)
      index = build_index() |> Search.remove!(doc)
      found_ids = Search.search(index, "Elixir") |> ids()
      refute 100 in found_ids
    end

    test "other documents remain after removal" do
      index = build_index() |> Search.remove!(List.first(@documents))
      assert [%{id: 101}] = Search.search(index, "Phoenix")
    end

    test "shared terms still work for remaining documents" do
      index = build_index() |> Search.remove!(List.first(@documents))
      results = Search.search(index, "Elixir")
      # doc 101 mentions Elixir in content
      assert ids(results) == [101]
    end

    test "removing all documents yields empty search results" do
      index = Enum.reduce(@documents, build_index(), &Search.remove!(&2, &1))
      assert Search.search(index, "Elixir") == []
      assert Search.search(index, "framework") == []
    end

    test "add then remove round-trips to equivalent behavior" do
      [d1, d2, d3] = @documents
      base = build_index([d1, d2])
      roundtripped = Search.add!(base, d3) |> Search.remove!(d3)

      # Same search behavior — not comparing internal structs
      for query <- ["Elixir", "Phoenix", "Nerves", "framework", "dynamic", "web"] do
        assert Search.search(base, query) == Search.search(roundtripped, query),
               "Mismatch for query: #{query}"
      end
    end

    test "raises DocumentMissingIdError without id" do
      assert_raise Search.DocumentMissingIdError, fn ->
        build_index() |> Search.remove!(%{title: "no id"})
      end
    end

    test "raises DocumentNotExistsError for unknown document" do
      assert_raise Search.DocumentNotExistsError, fn ->
        build_index() |> Search.remove!(%{id: 999, title: "nope"})
      end
    end

    test "raises DocumentMutatedError if document changed" do
      assert_raise Search.DocumentMutatedError, fn ->
        doc = List.first(@documents)
        build_index() |> Search.remove!(%{doc | title: "Changed"})
      end
    end

    test "handles string keys round-trip" do
      docs = [
        %{"id" => 1, "title" => "Divina Commedia", "text" => "Nel mezzo del cammin"},
        %{"id" => 2, "title" => "Promessi Sposi", "text" => "Quel ramo del lago"}
      ]

      extra = %{"id" => 3, "title" => "Vita Nova", "text" => "In quella parte del libro"}
      opts = [fields: ["title", "text"]]
      base = build_index(docs, opts)
      roundtripped = Search.add!(base, extra) |> Search.remove!(extra)

      for q <- ["del", "Divina", "ramo", "Vita"] do
        assert Search.search(base, q) == Search.search(roundtripped, q)
      end
    end
  end

  describe "remove/2" do
    test "returns {:ok, index} on success" do
      {:ok, index} = build_index() |> Search.remove(List.first(@documents))
      refute 100 in ids(Search.search(index, "Elixir"))
    end

    test "returns {:error, _} for unknown document" do
      assert {:error, _} = build_index() |> Search.remove(%{id: 999, title: "x"})
    end
  end

  # ---------------------------------------------------------------------------
  # search/3 — exact
  # ---------------------------------------------------------------------------
  describe "search/3 exact" do
    test "returns matching documents ranked by relevance" do
      results = build_index() |> Search.search("Elixir")
      # doc 100 has "Elixir" in title AND content, doc 101 only in content
      assert ids(results) == [100, 101]
      assert hd(scores(results)) > List.last(scores(results))
    end

    test "scores are positive floats" do
      results = build_index() |> Search.search("Elixir")
      assert Enum.all?(scores(results), &(is_float(&1) and &1 > 0))
    end

    test "result contains matched terms" do
      [r | _] = build_index() |> Search.search("Elixir")
      assert "elixir" in r.terms
    end

    test "result contains match field mapping" do
      [r | _] = build_index() |> Search.search("Elixir")
      assert :title in r.matches["elixir"]
      assert :content in r.matches["elixir"]
    end

    test "returns empty list for no match" do
      assert build_index() |> Search.search("Rustlang") == []
    end

    test "returns empty list for empty query" do
      assert build_index() |> Search.search("") == []
    end

    test "search is case-insensitive" do
      r1 = build_index() |> Search.search("elixir")
      r2 = build_index() |> Search.search("ELIXIR")
      assert ids(r1) == ids(r2)
      assert scores(r1) == scores(r2)
    end

    test "multi-term query matches documents containing any term" do
      results = build_index() |> Search.search("web dynamic")
      found = ids(results)
      # doc 100 has "dynamic", doc 101 has "web"
      assert 100 in found
      assert 101 in found
    end

    test "multi-term query: document matching both terms scores higher" do
      docs = [
        %{id: 1, title: "Elixir Phoenix", content: "web framework for Elixir"},
        %{id: 2, title: "Elixir", content: "a language"},
        %{id: 3, title: "Phoenix", content: "a framework"}
      ]

      results = build_index(docs) |> Search.search("Elixir Phoenix")
      # doc 1 matches both terms, should rank first
      assert hd(ids(results)) == 1
    end

    test "return_field_data includes requested fields" do
      index =
        Search.new(fields: [:title, :content], return_field_data: [:title])
        |> Search.add!(@documents)

      [r | _] = Search.search(index, "Elixir")
      assert r.fields[:title] == "Elixir"
    end

    test "return_field_data with string keys" do
      docs = [
        %{"id" => 1, "title" => "Hello", "text" => "world", "category" => "greeting"}
      ]

      index =
        Search.new(fields: ["title", "text"], return_field_data: ["category"])
        |> Search.add!(docs)

      [r] = Search.search(index, "Hello")
      assert r.fields["category"] == "greeting"
    end

    test "punctuation is stripped during tokenization" do
      docs = [%{id: 1, title: "hello", content: "world, foo. bar! baz?"}]
      index = build_index(docs)
      assert [%{id: 1}] = Search.search(index, "foo")
      assert [%{id: 1}] = Search.search(index, "bar")
      assert [%{id: 1}] = Search.search(index, "baz")
    end

    test "newlines are token boundaries" do
      docs = [%{id: 1, title: "x", content: "hello\nworld"}]
      index = build_index(docs)
      assert [%{id: 1}] = Search.search(index, "hello")
      assert [%{id: 1}] = Search.search(index, "world")
    end
  end

  # ---------------------------------------------------------------------------
  # search/3 — prefix
  # ---------------------------------------------------------------------------
  describe "search/3 prefix" do
    test "prefix matches longer terms" do
      results = build_index() |> Search.search("Eli", prefix?: true)
      assert 100 in ids(results)
    end

    test "prefix match scores lower than exact match" do
      index = build_index()
      [exact | _] = Search.search(index, "Elixir")
      [prefix | _] = Search.search(index, "Eli", prefix?: true)
      assert exact.score > prefix.score
    end

    test "exact + prefix combined: exact term gets full score, prefix extends reach" do
      index = build_index()
      exact_only = Search.search(index, "Elixir")
      with_prefix = Search.search(index, "Elixir", prefix?: true)
      # Same documents, same scores (prefix finds nothing extra beyond exact "Elixir")
      assert ids(exact_only) == ids(with_prefix)
      assert scores(exact_only) == scores(with_prefix)
    end

    test "prefix merges with exact matches across fields" do
      docs = [
        %{"id" => 1, "title" => "Divina Commedia", "text" => "Nel mezzo del cammin"},
        %{"id" => 2, "title" => "Promessi Sposi", "text" => "Quel ramo del lago"},
        %{"id" => 3, "title" => "Vita Nova", "text" => "In quella parte del libro della mia"}
      ]

      index = build_index(docs, fields: ["title", "text"])
      results = Search.search(index, "del", prefix?: true)
      # "del" exact matches all 3, "della" prefix matches doc 3
      assert length(results) == 3
      # doc 3 has both "del" (exact in text) and "della" (prefix), should rank high
      doc3 = Enum.find(results, &(&1.id == 3))
      assert map_size(doc3.matches) >= 2
    end
  end

  # ---------------------------------------------------------------------------
  # search/3 — fuzzy
  # ---------------------------------------------------------------------------
  describe "search/3 fuzzy" do
    test "finds terms within edit distance" do
      results = build_index() |> Search.search("lixir", fuzzy?: true)
      # "lixir" is edit distance 1 from "elixir"
      assert 100 in ids(results)
    end

    test "fuzzy match scores lower than exact match" do
      index = build_index()
      [exact | _] = Search.search(index, "Elixir")
      [fuzzy | _] = Search.search(index, "lixir", fuzzy?: true)
      assert exact.score > fuzzy.score
    end

    test "fuzzy does not double-count exact matches" do
      index = build_index()
      exact_only = Search.search(index, "Elixir")
      with_fuzzy = Search.search(index, "Elixir", fuzzy?: true)
      assert scores(exact_only) == scores(with_fuzzy)
    end

    test "fuzzy does not double-count prefix matches" do
      index = build_index()
      prefix_only = Search.search(index, "Elixi", prefix?: true)
      both = Search.search(index, "Elixi", prefix?: true, fuzzy?: true, fuzziness: 1)
      assert scores(prefix_only) == scores(both)
    end

    test "fuzziness: 0 behaves like exact match" do
      index = build_index()
      exact = Search.search(index, "Elixir")
      fuzzy_0 = Search.search(index, "Elixir", fuzzy?: true, fuzziness: 0)
      assert ids(exact) == ids(fuzzy_0)
      assert scores(exact) == scores(fuzzy_0)
    end

    test "fuzziness: 1 does not match terms at distance 2" do
      index = build_index()
      # "Phnix" is distance 2 from "phoenix"
      results = Search.search(index, "Phnix", fuzzy?: true, fuzziness: 1)
      refute 101 in ids(results)
    end

    test "fuzziness: 2 matches terms at distance 2" do
      index = build_index()
      # "Phnix" is distance 2 from "phoenix"
      results = Search.search(index, "Phnix", fuzzy?: true, fuzziness: 2)
      assert 101 in ids(results)
    end

    test "fuzzy with typo in multi-term query" do
      # "web famewrk" — "famewrk" is distance 2 from "framework"
      results = build_index() |> Search.search("web famewrk", prefix?: true, fuzzy?: true)
      assert 101 in ids(results)
    end

    test "fuzzy respects length bounds" do
      # fuzziness=1 means only terms within ±1 length are candidates
      docs = [
        %{id: 1, title: "cat", content: "the cat sat"},
        %{id: 2, title: "concatenate", content: "long word"}
      ]

      index = build_index(docs)
      # "bat" (len 3) at fuzziness 1 → candidates must be len 2..4
      # "cat" (len 3) qualifies, "concatenate" (len 11) does not
      results = Search.search(index, "bat", fuzzy?: true, fuzziness: 1)
      assert 1 in ids(results)
      refute 2 in ids(results)
    end
  end

  # ---------------------------------------------------------------------------
  # search/3 — scoring properties
  # ---------------------------------------------------------------------------
  describe "search/3 scoring" do
    test "term in title and content scores higher than content only" do
      # doc 100 has "Elixir" in both title and content
      # doc 101 has "Elixir" only in content
      results = build_index() |> Search.search("Elixir")
      assert ids(results) == [100, 101]
    end

    test "rarer terms score higher (IDF effect)" do
      docs = [
        %{id: 1, title: "common rare", content: "common common common"},
        %{id: 2, title: "common", content: "common common"}
      ]

      index = build_index(docs)
      rare_results = Search.search(index, "rare")
      common_results = Search.search(index, "common")
      # "rare" appears in 1 doc, "common" in 2 — rare should score higher for its match
      rare_score = hd(scores(rare_results))
      common_score = hd(scores(common_results))
      assert rare_score > common_score
    end

    test "custom weights affect prefix and fuzzy scores" do
      index = build_index()
      default = Search.search(index, "Eli", prefix?: true)
      boosted = Search.search(index, "Eli", prefix?: true, weights: [prefix: 0.9])
      assert hd(scores(boosted)) > hd(scores(default))
    end
  end

  # ---------------------------------------------------------------------------
  # larger corpus
  # ---------------------------------------------------------------------------
  describe "larger corpus" do
    @tag :larger_corpus
    setup do
      docs =
        for i <- 1..200 do
          %{
            id: i,
            title: "Document #{i}",
            content: "This is document number #{i} with some content about topic #{rem(i, 10)}"
          }
        end

      %{index: build_index(docs)}
    end

    test "exact search returns correct document", %{index: index} do
      results = Search.search(index, "200")
      assert 200 in ids(results)
    end

    test "all documents are searchable", %{index: index} do
      # "document" appears in every doc
      results = Search.search(index, "document")
      assert length(results) == 200
    end

    test "prefix search works at scale", %{index: index} do
      results = Search.search(index, "doc", prefix?: true)
      assert length(results) == 200
    end

    test "fuzzy search works at scale", %{index: index} do
      # "documnt" is distance 1 from "document"
      results = Search.search(index, "documnt", fuzzy?: true, fuzziness: 1)
      assert length(results) == 200
    end

    test "add then remove at scale preserves other results", %{index: index} do
      doc = %{id: 9999, title: "Temporary", content: "ephemeral data"}
      updated = Search.add!(index, doc) |> Search.remove!(doc)
      assert Search.search(index, "document") == Search.search(updated, "document")
    end
  end
end
