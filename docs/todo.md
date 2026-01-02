# TODO

- [x] backup/1
- [x] restore/1
- [x] backup!/1
- [x] restore!/1
- [x] mix tasks
- [x] release tasks
- [x] release script generator
- [x] scheduler
- [x] Make restore work on multiple repos
- [ ] Make default backup file name and default restore file name customizable via callback
- [ ] Types: `repo_spec()`, `repo_config()`
- [x] If not specified, use latest backup in `backup_dir` for `restore_file`
- [x] Add `-f` option to mix/release tasks to specify backup/restore file per repo
- [x] Modify restore confirmation to confirm each repo when restoring multiple repos
- [x] Make confirmation require typing the full "RepoName" instead of just "yes"
- [x] Add `--confirm RepoName` option to mix/release tasks to skip confirmation for that repo
- [ ] Add extensions
- [ ] CI tests
- [ ] Allow scheduled restores? Might be useful for auto-resetting demo sites or staging
  environments but also dangerous.
- [ ] Make total in progress telemetry events optional.

## Adapters
- [x] Postgres
- [ ] MySQL
- [ ] SQLite

## Post-backup extensions
- [ ] file pruning
- [ ] file cp
- [ ] rsync upload
- [ ] scp upload
- [ ] object storage upload
- [ ] object storage pruning

## Pre-restore handlers
- [ ] rsync download
- [ ] scp download
- [ ] object storage download
