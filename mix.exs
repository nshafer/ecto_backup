defmodule EctoBackup.MixProject do
  use Mix.Project

  @source_url "https://github.com/nshafer/ecto_backup"
  @version "0.1.0"

  def project do
    [
      app: :ecto_backup,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: test_coverage(),
      docs: docs()
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {EctoBackup.Application, []}
    ]
  end

  defp test_coverage do
    [
      ignore_modules: [
        Collectable.EctoBackup.CLI,
        EctoBackup.TestRepo,
        EctoBackup.SecondTestRepo,
        EctoBackup.TestPGRepo,
        EctoBackup.SecondTestPGRepo,
        EctoBackup.StubAdapter,
        EctoBackup.StubEctoAdapter
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, "~> 3.2"},
      {:telemetry, "~> 0.4 or ~> 1.0"},
      {:temp, "~> 0.4"},
      {:crontab, "~> 1.2.0"},
      {:postgrex, ">= 0.0.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false, warn_if_outdated: true},
      {:earmark, ">= 0.0.0", only: :dev, runtime: false},
      {:mix_test_interactive, "~> 5.0", only: :dev, runtime: false},
      {:patch, "~> 0.16.0", only: [:test]},
      # Highlander is only included so ex_doc doesn't generate warnings
      {:highlander, ">= 0.0.0", only: :dev},
      {:highlander_pg, ">= 0.0.0", only: :dev}
    ]
  end

  defp aliases do
    [
      "test.i": ["test.interactive"],
      precommit: ["compile --warning-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end

  defp docs do
    [
      main: "EctoBackup",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/ecto_backup",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md", "LICENSE.md"],
      main: "readme",
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      groups_for_modules: [
        "Built-in Adapters": [
          EctoBackup.Adapter,
          EctoBackup.Adapters.Postgres
        ],
        Utilities: [
          EctoBackup.Conf,
          EctoBackup.CLI,
          EctoBackup.CLI.Shell,
          EctoBackup.CLI.Shell.IO,
          EctoBackup.CLI.Shell.Process,
          EctoBackup.CLI.Shell.Quiet
        ]
      ]
    ]
  end
end
