# EctoBackup

Simple backup (and restore) for small to medium projects.

EctoBackup provides Mix tasks and release functions to backup and restore Ecto repositories in dev
and production, manually and on a schedule.

## Supported Databases

- PostgreSQL (via `pg_dump` and `pg_restore`)
- (More databases coming soon!)

## Features

- Easy to use Mix tasks for backup and restore.
- Release functions for performing backup and restore in production releases.
- Scheduled automatic backups with cron-like scheduling.
- Support for backing up multiple Ecto repositories in a single operation.
- Configuration options for customizing backup and restore behavior globally or per-repo.
- Progress reporting and logging during backup and restore operations.

## Installation

The package can be installed by adding `ecto_backup` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ecto_backup, "~> 0.1.0"}
  ]
end
```

Configure the list of repositories to backup by default, and where to store the backups.

```elixir
config :ecto_backup,
  repos: [MyApp.Repo],
  backup_path: "/path/to/backups"
```

See the [documentation](https://hexdocs.pm/ecto_backup/EctoBackup.html) for more information on
configuration and usage.

**Optional:** Create aliases for the Mix tasks in your `mix.exs` file:

```elixir
defp aliases do
  [
    "ecto.backup": ["ecto_backup.backup"],
    "ecto.restore": ["ecto_backup.restore"]
  ]
end
```

**Optional:** Create release shell scripts to run the backup and restore tasks in your release
environment. See [EctoBackup.Release](https://hexdocs.pm/ecto_backup/EctoBackup.Release.html) for
more information.

```bash
$ mix ecto_backup.gen.release
```

## Usage

In environments with Mix (development, test):

```bash
$ mix ecto_backup.backup
$ mix ecto_backup.restore /path/to/backup/file.db
```

In release environments:

```bash
$ bin/backup
$ bin/restore /path/to/backup/file.db
```

## Documentation

The documentation for EctoBackup can be found at
[https://hexdocs.pm/ecto_backup](https://hexdocs.pm/ecto_backup).

## Contributing

Contributions are welcome! Please open issues and submit pull requests on the
[GitHub repository](https://github.com/nshafer/ecto_backup).

## License

EctoBackup is released under the MIT License. See the [LICENSE.md](LICENSE.md) file for details.
