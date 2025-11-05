# Notes

## Features

- Can backup supported Ecto databases just by installing the module.
- Can restore supported Ecto databases from a file.
- Can backup/restore via mix task, release task, by custom code, or schedule.
- Backs up to local file.
- Can upload file somewhere, using adapters.
- Has facility to backup on regular schedule, uniquely in a cluster.
- Has facility to prune backups, locally and on remote.
- Can configure globally, per repo, or override on call to API.

## Config

Configuration can be done globally

```elixir
config :ecto_backup,
  ecto_repos: [EctoBackup.Repo],
  backup_dir: "local/backups"  
```

Per repo:

```elixir
config :ecto_backup, Myapp.Repo
  backup_dir: "local/backups",
  username: "readonlyuser"
```

Or on each call to the API

```elixir
EctoBackup.backup(repo: Myapp.Repo, adapter: EctoBackup.Adapters.Postgres, username: "readonlyuser")
```

## API

- `EctoBackup.backup/1` will backup the database and return `{:ok, backup_file}` or `{:error, reason}`.
    - More of a low-level, direct method of running the backup. By default will be silent and block until done.
    - Takes all options, overriding repo/global config with same key. Does not restrict options so that third-party
      adapters can get whatever options they want.
    - Has option for `feedback: MyModule`, which must implement `EctoBackup.Feedback` behaviour, which has functions
      that receive feedback on the backup process. Start, progress, info, done, etc.
    - This is what the scheduled backup will call, as it does not need to output any progress, just cares about result.
- `EctoBackup.backup!/1` will do the same as `backup`, but by default outputs to stdout with progress, info, etc.
    - Will raise exception on any error.
    - This is what the mix task and release task will use.
- `EctoBackup.restore/1` will restore the database from the given file.
    - Low-level function that is unused by default. Here for custom work-flows.
    - Doesn't output anything, just returns result.
- `EctoBackup.restore!/1` will do the same as `restore`
    - Prompts user for confirmation, outputs status, raises on exception.
    - This is what the mix task and release task will use.
