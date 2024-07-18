defmodule Search.MixProject do
  use Mix.Project

  @version "0.2.0"
  @repo_url "https://github.com/elliotekj/search"

  def project do
    [
      app: :search,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: description(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:typed_struct, "~> 0.3"},
      {:radix, "~> 0.5"},
      {:leven, "~> 1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Elliot Jackson"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @repo_url}
    ]
  end

  defp description do
    """
    ⚡ Fast full-text search for Elixir
    """
  end

  defp docs do
    [
      name: "Search",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/search",
      source_url: @repo_url
    ]
  end
end
