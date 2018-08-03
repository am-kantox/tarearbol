defmodule Tarearbol.Mixfile do
  @moduledoc false

  use Mix.Project

  @app :tarearbol
  @app_name "Tarearbol"
  @version "0.8.1"

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
      docs: docs()
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
      {:envio, ">= 0.3.2"},

      {:credo, "~> 0.8", only: :dev},
      {:ex_doc, "~> 0.11", only: :dev},
      {:mock, "~> 0.2", only: :test},
      {:stream_data, "~>0.4", only: :test}
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

  defp docs() do
    [
      main: @app_name,
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/#{@app}",
      logo: "stuff/images/logo.png",
      source_url: "https://github.com/am-kantox/#{@app}",
      extras: [
        "stuff/pages/intro.md"
      ],
      groups_for_modules: [
        # Tarearbol

        "Exceptions": [
          Tarearbol.TaskFailedError
        ]
      ]
    ]
  end
end
