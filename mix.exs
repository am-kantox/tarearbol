defmodule Tarearbol.Mixfile do
  @moduledoc false

  use Mix.Project

  @app :tarearbol
  @version "1.2.1"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: compilers(Mix.env()),
      preferred_cli_env: ["test.cluster": :ci],
      package: package(),
      description: description(),
      deps: deps(),
      aliases: aliases(),
      xref: [exclude: []],
      docs: docs(),
      releases: [
        {@app,
         [
           include_executables_for: [:unix],
           applications: [logger: :permanent]
         ]}
      ],
      dialyzer: [
        plt_file: {:no_warn, ".dialyzer/plts/dialyzer.plt"},
        plt_add_deps: :transitive,
        plt_add_apps: [:mix],
        list_unused_filters: true,
        ignore_warnings: ".dialyzer/ignore.exs"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: extra_applications(Mix.env()),
      mod: {Tarearbol.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:formulae, "~> 0.5"},
      {:boundary, "~> 0.4"},
      {:telemetria, "~> 0.5", optional: true},
      {:cloister, "~> 0.1", optional: true},
      # dev / test
      {:credo, "~> 1.0", only: [:dev, :ci]},
      {:dialyxir, "~> 1.0", only: [:dev, :test, :ci], runtime: false},
      {:benchfella, "~> 0.3", only: [:dev]},
      {:ex_doc, "~> 0.11", only: :dev},
      {:test_cluster_task, "~> 0.1", only: [:test, :ci]},
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
        "stuff/pages/dynamic_workers_management.md",
        "stuff/pages/cron_management.md"
      ],
      groups_for_modules: [
        "Task Sugar": [
          Tarearbol
        ],
        "Dymanic Supervisor Sugar": [
          Tarearbol.DynamicManager
        ],
        Scheduler: [
          Tarearbol.Calendar,
          Tarearbol.Crontab,
          Tarearbol.Scheduler,
          Tarearbol.Scheduler.Job
        ],
        Exceptions: [
          Tarearbol.TaskFailedError
        ]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:ci), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp extra_applications(:test), do: [:logger, :stream_data, :telemetria]
  defp extra_applications(:ci), do: [:logger, :cloister, :stream_data]
  defp extra_applications(:dev), do: [:logger]
  defp extra_applications(:prod), do: [:logger]

  defp compilers(:test), do: [:boundary, :telemetria | Mix.compilers()]
  defp compilers(:prod), do: Mix.compilers()
  defp compilers(_), do: [:boundary | Mix.compilers()]
end
