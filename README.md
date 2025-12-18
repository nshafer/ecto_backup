# EctoBackup

Simple backup (and restore) for small to medium projects.

EctoBackup provides Mix tasks and release functions to backup and restore Ecto repositories in dev
and production, manually and on a schedule.

### Supported Databases

- PostgreSQL (via `pg_dump` and `pg_restore`)
- (More databases coming soon!)

### Features

- Easy to use Mix tasks for backup and restore.
- Release functions for performing backup and restore in production releases.
- Scheduled automatic backups with cron-like scheduling.
- Support for backing up multiple Ecto repositories in a single operation.
- Configuration options for customizing backup and restore behavior globally or per-repo.
- Progress reporting and logging during backup and restore operations.

> #### Warning {: .warning}
>
> This library provides simple backup and restore functionality for Ecto repositories, it may
> not be a complete backup solution for all use cases. It is recommended to evaluate your
> specific backup and restore requirements and ensure that this library meets those needs before
> relying on it for critical data protection. Always test your backups and restores to ensure
> they work as expected. Always keep your backups secure and follow best practices for data
> protection.

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

Configure the list of repositories to backup by default, and where to store the backups.

```elixir
config :ecto_backup,
  repos: [MyApp.Repo],
  backup_path: "/path/to/backups"
```

See [EctoBackup](https://hexdocs.pm/ecto_backup/EctoBackup.html) for more information on
configuration and usage.

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
information on scheduling options.

### (Optional) Mix Aliases

Create aliases for the Mix tasks in your `mix.exs` file:

```elixir
defp aliases do
  [
    "ecto.backup": ["ecto_backup.backup"],
    "ecto.restore": ["ecto_backup.restore"]
  ]
end
```

### (Optional) Release Scripts

Create release shell scripts to run the backup and restore tasks in your release
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
