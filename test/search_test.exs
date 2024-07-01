defmodule SearchTest do
  @moduledoc false
  use ExUnit.Case, async: true
  doctest Search

  @documents [
    %{
      id: 100,
      title: "Elixir",
      content: "Elixir is a dynamic, functional language.",
      tag: "lang"
    },
    %{
      id: 101,
      title: "Phoenix",
      content: "Phoenix is a web framework for Elixir.",
      tag: "framework"
    },
    %{
      id: 102,
      title: "Nerves",
      content: "Nerves is a framework for embedded systems.",
      tag: "framework"
    }
  ]

  @opts [fields: [:title, :content]]

  describe "new/1" do
    test "raises KeyError if fields is missing" do
      assert_raise KeyError, fn ->
        Search.new(return_field_data: [:title])
      end
    end

    test "initializes default index" do
      index = Search.new(fields: [:title])

      assert index.tree == {0, nil, nil}
      assert index.document_count == 0
      assert index.next_id == 1
      assert index.ids == %{}
      assert index.short_ids == %{}
      assert index.return_field_data == %{}
      assert index.return_fields == []
      assert index.avg_field_lengths == %{}
      assert index.field_lengths == %{}
      assert index.fields == [title: 0]
    end
  end

  describe "add!/2" do
    test "adds documents to index" do
      doc = List.first(@documents)
      index = Search.new(@opts)
      index = Search.add!(index, doc)
      assert index.document_count == 1
    end

    test "does not error if field is missing" do
      index = Search.new(fields: [:title, :text])
      index = Search.add!(index, %{id: 1, text: "Nel mezzo del cammin di nostra vita"})
      assert index.document_count == 1
    end

    test "raises DocumentMissingIdError if document does not have an id" do
      assert_raise Search.DocumentMissingIdError, fn ->
        Search.new(fields: [:title, :text]) |> Search.add!(%{title: "Moby Dick"})
      end
    end

    test "raises DocumentExistsError if ids are repeated" do
      assert_raise Search.DocumentExistsError, fn ->
        index = Search.new(@opts)
        index = Search.add!(index, %{id: 1, title: "Moby Dick"})
        Search.add!(index, %{id: 1, title: "Moby Dick"})
      end
    end

    test "stringifies document fields that implement String.Chars" do
      {:ok, _index} =
        Search.new(fields: [:title, :text])
        |> Search.add(%{id: 100, title: 100, text: "Moby Dick"})
    end

    test "raises DocumentFieldNotString if a document field is not a string" do
      assert_raise Search.DocumentFieldNotString, fn ->
        Search.new(fields: [:title, :text])
        |> Search.add!(%{
          id: 100,
          title: 100,
          text: %{title: "Moby Dick", author: "Herman Melville"}
        })
      end
    end
  end

  describe "add/2" do
    test "adds a document to the index" do
      doc = List.first(@documents)
      index = Search.new(@opts)
      {:ok, index} = Search.add(index, doc)
      assert index.document_count == 1
    end

    test "adds documents to the index" do
      index = Search.new(@opts)
      {:ok, index} = Search.add(index, @documents)
      assert index.document_count == 3
    end

    test "errors if first document is missing an id" do
      index = Search.new(fields: [:title, :text])
      {:error, "Document is missing an ID."} = Search.add(index, %{title: "Moby Dick"})
    end

    test "errors nth document is missing an id" do
      index = Search.new(fields: [:title, :text])

      {:error, "Document is missing an ID."} =
        Search.add(index, [%{id: 1, title: "Moby Dick"}, %{title: "Moby Dick"}])
    end
  end

  describe "remove!/2" do
    test "raises DocumentMissingIdError if document does not have an id" do
      assert_raise Search.DocumentMissingIdError, fn ->
        Search.new(@opts)
        |> Search.add!(%{id: 1, title: "Moby Dick"})
        |> Search.remove!(%{title: "Moby Dick"})
      end
    end

    test "resets index if last document is removed" do
      doc = List.first(@documents)
      index = Search.new(fields: [:title, :text])
      index = Search.add!(index, doc)
      assert index.document_count == 1
      index = Search.remove!(index, doc)

      assert index.tree == {0, nil, nil}
      assert index.document_count == 0
      assert index.next_id == 2
      assert index.ids == %{}
      assert index.short_ids == %{}
      assert index.return_field_data == %{}
      assert index.return_fields == []
      assert index.avg_field_lengths == %{}
      assert index.field_lengths == %{}
      assert index.fields == [title: 0, text: 1]
    end

    test "removes document from index" do
      index = Search.new(@opts)
      index = Search.add!(index, @documents)
      assert index.document_count == 3
      index = Search.remove!(index, List.first(@documents))

      assert index.document_count == 2
      assert index.next_id == 4
      assert index.ids == %{101 => 2, 102 => 3}
      assert index.short_ids == %{2 => 101, 3 => 102}
      assert index.return_field_data == %{2 => %{}, 3 => %{}}
      assert index.return_fields == []
      assert index.avg_field_lengths == %{0 => 1.0, 1 => 7.0}
      assert index.field_lengths == %{2 => [1, 7], 3 => [1, 7]}
      assert index.fields == [title: 0, content: 1]

      assert Search.search(index, "Ruby") == []

      assert Search.search(index, "Phoenix") == [
               %{
                 fields: %{},
                 id: 101,
                 matches: %{"phoenix" => [:title, :content]},
                 score: 2.0794415416798357,
                 terms: ["phoenix"]
               }
             ]
    end

    test "cleans up document data on removal" do
      [doc_1, doc_2, doc_3] = @documents
      old_index = Search.new(@opts) |> Search.add!([doc_1, doc_2])
      new_index = Search.add!(old_index, doc_3) |> Search.remove!(doc_3)
      new_index = %{new_index | next_id: old_index.next_id}
      assert old_index == new_index
    end

    test "does not remove terms for other documents" do
      index =
        Search.new(@opts)
        |> Search.add!(@documents)
        |> Search.remove!(List.first(@documents))

      assert Search.search(index, "Elixir") |> length() == 1
    end

    test "handles string keys" do
      documents = [
        %{
          "id" => 100,
          "title" => "Divina Commedia",
          "text" => "Nel mezzo del cammin di nostra vita"
        },
        %{
          "id" => 101,
          "title" => "I Promessi Sposi",
          "text" => "Quel ramo del lago di Como",
          "lang" => "it",
          "category" => "fiction"
        }
      ]

      document = %{
        "id" => 102,
        "title" => "Vita Nova",
        "text" => "In quella parte del libro della mia memoria",
        "category" => "poetry"
      }

      old_index =
        Search.new(fields: ["title", "text"], return_field_data: ["lang", "category"])
        |> Search.add!(documents)

      new_index = Search.add!(old_index, document) |> Search.remove!(document)
      new_index = %{new_index | next_id: old_index.next_id}
      assert old_index == new_index
    end

    test "raises DocumentNotExistsError if the document does not exist in the index" do
      assert_raise Search.DocumentNotExistsError, fn ->
        Search.new(@opts)
        |> Search.add!(@documents)
        |> Search.remove!(%{id: 1000, title: "Moby Dick"})
      end
    end

    test "raises DocumentMutatedError if the document has changed" do
      assert_raise Search.DocumentMutatedError, fn ->
        doc = List.first(@documents)
        mutated_doc = %{doc | title: "Unknown"}

        Search.new(@opts)
        |> Search.add!(doc)
        |> Search.remove!(mutated_doc)
      end
    end
  end

  describe "search/2" do
    test "scores results" do
      index = Search.new(@opts) |> Search.add!(@documents)
      results = Search.search(index, "Elixir")
      assert length(results) == 2
      assert Enum.map(results, & &1.id) == [100, 101]
      assert Enum.map(results, & &1.score) == [2.194907312448878, 0.6962007371655166]
    end

    test "returns stored fields in result" do
      index =
        Search.new(fields: [:title, :content], return_field_data: [:title, :tags])
        |> Search.add!(@documents)

      results = Search.search(index, "Elixir")
      assert length(results) == 2
      assert Enum.map(results, &get_in(&1, [:fields, :title])) == ["Elixir", "Phoenix"]
      assert Enum.map(results, &get_in(&1, [:fields, :tag])) == [nil, nil]
    end

    test "handles string keys" do
      documents = [
        %{
          "id" => 100,
          "title" => "Divina Commedia",
          "text" => "Nel mezzo del cammin di nostra vita"
        },
        %{
          "id" => 101,
          "title" => "I Promessi Sposi",
          "text" => "Quel ramo del lago di Como",
          "lang" => "it",
          "category" => "fiction"
        },
        %{
          "id" => 102,
          "title" => "Vita Nova",
          "text" => "In quella parte del libro della mia memoria",
          "category" => "poetry"
        }
      ]

      index =
        Search.new(fields: ["title", "text"], return_field_data: ["lang", "category"])
        |> Search.add!(documents)

      results = Search.search(index, "del")
      assert length(results) == 3
      assert Enum.map(results, &get_in(&1, [:fields, "lang"])) == ["it", nil, nil]
      assert Enum.map(results, &get_in(&1, [:fields, "category"])) == ["fiction", nil, "poetry"]
    end

    test "returns empty array if no results are found" do
      index = Search.new(@opts) |> Search.add!(@documents)
      assert Search.search(index, "not-found") == []
    end

    test "returns empty array if query is empty string" do
      index = Search.new(@opts) |> Search.add!(@documents)
      assert Search.search(index, "") == []
    end
  end
end
