# Search

[![Hex.pm Version](http://img.shields.io/hexpm/v/search.svg?style=flat)](https://hex.pm/packages/search)
[![Docs](https://img.shields.io/badge/Docs-Yes-blue)](https://hexdocs.pm/search/search.html)
[![Hex.pm License](http://img.shields.io/hexpm/l/search.svg?style=flat)](https://hex.pm/packages/search)

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
- 🔜 Weighted fields
- 🔢 Modern search result ranking algorithm
- 🔀 Add and remove documents anytime

## Installation

The package can be installed by adding `search` to your list of dependencies in
`mix.exs`:

```elixir
def deps do
  [
    {:search, "~> 0.2"}
  ]
end
```

## Usage

### Creating an Index

To create a new index, use the `new/1` function with a list of fields to be
indexed:

    index = Search.new(fields: [:title, :content])

### Adding Documents

To add a document to the index, use the `add/2` function with the index and the
document:

    document = %{id: 1, title: "Elixir", content: "Elixir is a dynamic, functional language."}
    index = Search.add!(index, document)

You can also add multiple documents at once:

    documents = [
      %{id: 2, title: "Phoenix", content: "Phoenix is a web framework for Elixir."},
      %{id: 3, title: "Nerves", content: "Nerves is a framework for embedded systems."}
    ]
    index = Search.add!(index, documents)

### Removing Documents

To remove a document from the index, use the `remove/2` function with the index
and the document:

    index = Search.remove!(index, document)

You can also remove multiple documents at once:

    index = Search.remove!(index, documents)

### Searching

To search the index, use the `search/3` function with the index and the query
string:

    Search.search(index, "Eli", prefix?: true)
    [
      %{
        id: 1,
        matches: %{"elixir" => [:title, :content]},
        fields: %{},
        terms: ["elixir"],
        score: 0.7157306453637646
      },
      %{
        id: 2,
        matches: %{"elixir" => [:content]},
        fields: %{},
        terms: ["elixir"],
        score: 0.22702197951049452
      }
    ]

## Internals

The library uses a Radix tree for efficient indexing and retrieval of terms.
It also implements the BM25 algorithm for relevance scoring.

## License

`Search` is released under the [`Apache License
2.0`](https://github.com/elliotekj/search/blob/main/LICENSE).

## About

This package was written by [Elliot Jackson](https://elliotekj.com).

- Blog: [https://elliotekj.com](https://elliotekj.com)
- Email: elliot@elliotekj.com