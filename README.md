# EctoBackup

[![Hex.pm](https://img.shields.io/hexpm/v/ecto_backup.svg)](https://hex.pm/packages/ecto_backup)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/ecto_backup/)

Simple backup (and restore) for small to medium projects.

Provides a toolkit for easy backups and restores of Ecto repositories in development environments
via Mix tasks, and in production environments via release scripts, with support for scheduling
automatic backups with cron syntax.

### Features

- Easy to use Mix tasks for backup and restore in dev and test environments.
- Release tasks for performing backup and restore in production releases.
- Scheduled automatic backups with cron-like scheduling on a per-repo basis.
- Support for backing up (and restoring) multiple Ecto repositories in a single operation.
- Configuration options for customizing backup and restore behavior globally or per-repo.
- Progress reporting and logging during backup and restore operations for CLI feedback.
- Pluggable adapters to support any database supported by Ecto.

> #### Warning {: .warning}
>
> This library provides simple backup and restore functionality for Ecto repositories, it may
> not be a complete backup solution for all use cases. It is recommended to evaluate your
> specific backup and restore requirements and ensure that this library meets those needs before
> relying on it for critical data protection. Always test your backups and restores to ensure
> they work as expected. Always keep your backups secure and follow best practices for data
> protection.

### Supported Databases

- PostgreSQL (via `pg_dump` and `pg_restore`)
- MySQL / MariaDB (via `mysqldump` and `mysql`) **\*COMING SOON**
- SQLite (via VACUUM INTO) **\*COMING SOON**

## Installation

The package can be installed by adding `ecto_backup` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ecto_backup, "~> 0.1.0"}
  ]
end
```

Then, run `mix deps.get` to fetch the new dependency.

### Example Configuration

Configure the default list of repositories to backup and where to store the backups. These are
required for normal operation, such as being able to just call `mix ecto_backup.backup`. They can
be overridden when using mix tasks, release tasks, scheduled backups, or direct API calls. They
can also be overridden on a per-repo basis.

```elixir
config :ecto_backup,
  repos: [MyApp.Repo],
  backup_path: "/path/to/backups"
```

See [EctoBackup](https://hexdocs.pm/ecto_backup/EctoBackup.html) for more information on
configuration and usage, and the [Backup Mix
Task](https://hexdocs.pm/ecto_backup/Mix.Tasks.EctoBackup.Backup.html), [Restore Mix
Task](https://hexdocs.pm/ecto_backup/Mix.Tasks.EctoBackup.Restore.html), [Release
Module](https://hexdocs.pm/ecto_backup/EctoBackup.Release.html), and
[Scheduler](https://hexdocs.pm/ecto_backup/EctoBackup.Scheduler.html) for more information on
those components.

### (Optional) Enabled Scheduled Backups

To enable scheduled backups, add the `EctoBackup.Scheduler` to your supervision tree:

```elixir
# application.ex
children = [
  # Other children...
  EctoBackup.Scheduler
]

# config.exs
config :ecto_backup,
  repos: [MyApp.Repo],
  backup_path: "/path/to/backups",
  backup_schedule: "0 2 * * *",  # Every day at 2 AM (cron format)
  backup_stagger_sec: 600,       # Random delay up to 600 seconds
  backup_node: :my_app@my_host   # Node to perform the backup on
```

See [EctoBackup.Scheduler](https://hexdocs.pm/ecto_backup/EctoBackup.Scheduler.html) for more
information on scheduling options, including backing up multiple repos on different schedules.

### (Optional) Mix Aliases

Create aliases for the Mix tasks in your `mix.exs` file to save a few keystrokes:

```elixir
defp aliases do
  [
    "ecto.backup": ["ecto_backup.backup"],
    "ecto.restore": ["ecto_backup.restore"]
  ]
end
```

If, in the future, Ecto adds built-in backup and restore tasks, you can easily change or remove
your aliases to use those instead.

### (Optional) Release Scripts

Create release shell scripts to run the backup and restore tasks in your release
environment. See [EctoBackup.Release](https://hexdocs.pm/ecto_backup/EctoBackup.Release.html) for
more information.

```bash
$ mix ecto_backup.gen.release
```

This will create two scripts, `backup` and `restore`, in the `rel/commands` directory. You can
customize these scripts as needed, then copy them to your release's `bin` directory during
deployment. By default they simply use the `eval` command to run the appropriate functions in the
`EctoBackup.Release` module. They take all of the same options as the Mix tasks, and have the same
behavior and functionality.

## Usage

In environments with Mix (development, test):

```bash
$ mix ecto_backup.backup
$ mix ecto_backup.restore /path/to/backup/file.db
```

In release environments (without Mix, such as production and staging):

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
