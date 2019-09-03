defmodule Tarearbol.Mixfile do
  @moduledoc false

  use Mix.Project

  @app :tarearbol
  @version "0.12.0"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      package: package(),
      xref: [exclude: []],
      description: description(),
      deps: deps(),
      aliases: aliases(),
      xref: [exclude: []],
      docs: docs(),
      dialyzer: [
        plt_file: {:no_warn, ".dialyzer/plts/dialyzer.plt"},
        ignore_warnings: ".dialyzer/ignore.exs"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :envio],
      mod: {Tarearbol.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:envio, "~> 0.5"},
      {:formulae, "~> 0.5"},
      {:credo, "~> 1.0", only: [:dev, :ci]},
      {:dialyxir, "~> 1.0.0-rc.6", only: [:dev, :test, :ci], runtime: false},
      {:ex_doc, "~> 0.11", only: :dev},
      {:mock, "~> 0.2", only: [:test, :ci]},
      {:stream_data, "~> 0.4", only: [:test, :ci]}
    ]
  end

  defp aliases do
    [
      quality: ["format", "credo --strict", "dialyzer"],
      "quality.ci": [
        "format --check-formatted",
        "credo --strict",
        "dialyzer --halt-exit-status"
      ]
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
      links: %{
        "GitHub" => "https://github.com/am-kantox/#{@app}",
        "Docs" => "https://hexdocs.pm/#{@app}"
      }
    ]
  end

  defp docs do
    [
      main: "intro",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/#{@app}",
      logo: "stuff/images/logo.png",
      source_url: "https://github.com/am-kantox/#{@app}",
      assets: "stuff/images",
      extras: [
        "stuff/pages/intro.md",
        "stuff/pages/task_management.md",
        "stuff/pages/dynamic_workers_management.md"
      ],
      groups_for_modules: [
        # Tarearbol

        Exceptions: [
          Tarearbol.TaskFailedError
        ]
      ]
    ]
  end
end
