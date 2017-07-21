defmodule Tarearbol.Mixfile do
  use Mix.Project

  @app :tarearbol

  def project do
    [
      app: @app,
      version: "0.1.0",
      elixir: "~> 1.4",
      start_permanent: Mix.env == :prod,
      package: package(),
      description: description(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Tarearbol.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
    ]
  end

  defp description do
    """
    The supervised tree of tasks, simplifying the process of handling:

    - recurrent tasks
    - retried tasks
    - long tasks
    - etc
    """
  end

  defp package do
    [
     name: @app,
     files: ~w|config lib mix.exs README.md|,
     maintainers: ["Aleksei Matiushkin"],
     licenses: ["MIT"],
     links: %{"GitHub" => "https://github.com/mudasobwa/#{@app}",
              "Docs" => "https://hexdocs.pm/#{@app}"}]
  end
end
