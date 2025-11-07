defmodule EctoBackup.MixProject do
  use Mix.Project

  def project do
    [
      app: :ecto_backup,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: test_coverage()
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp test_coverage do
    [
      ignore_modules: [
        EctoBackup.TestPGRepo,
        EctoBackup.UnsupportedAdapter,
        EctoBackup.UnsupportedRepo
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
      {:mix_test_interactive, "~> 5.0", only: :dev, runtime: false},
      {:patch, "~> 0.16.0", only: [:test]}
    ]
  end

  defp aliases do
    [
      testi: ["test.interactive"],
      precommit: ["compile --warning-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
