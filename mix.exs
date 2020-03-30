defmodule Tarearbol.Mixfile do
  @moduledoc false

  use Mix.Project

  @app :tarearbol
  @version "0.99.3"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      preferred_cli_env: ["test.cluster": :test],
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
           applications: [logger: :permanent, envio: :permanent]
         ]}
      ],
      dialyzer: [
        plt_file: {:no_warn, ".dialyzer/plts/dialyzer.plt"},
        plt_add_deps: :transitive,
        plt_add_apps: [:mix],
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
      {:cloister, "~> 0.1"},
      # dev / test
      {:credo, "~> 1.0", only: [:dev, :ci]},
      {:dialyxir, "~> 1.0.0-rc.6", only: [:dev, :test, :ci], runtime: false},
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
  defp elixirc_paths(:dev), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
