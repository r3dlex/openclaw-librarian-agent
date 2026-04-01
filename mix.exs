defmodule Librarian.MixProject do
  use Mix.Project

  def project do
    [
      app: :librarian,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [
        summary: [threshold: 80],
        ignore_modules: [
          Librarian.Application,
          Librarian.IAMQ,
          Librarian.MqWsClient,
          Librarian.Vault.Watcher,
          Librarian.Atlassian.Client,
          Librarian.Input,
          Librarian.Repo,
          Librarian.Reporter,
          Librarian.Archiver,
          Librarian.StagingWorker
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Librarian.Application, []}
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.12"},
      {:ecto_sqlite3, "~> 0.17"},
      {:file_system, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:websockex, "~> 0.5"},
      {:yaml_elixir, "~> 2.11"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.create", "ecto.migrate"],
      "librarian.process_input": ["run", "lib/mix/tasks/process_input.ex"]
    ]
  end
end
