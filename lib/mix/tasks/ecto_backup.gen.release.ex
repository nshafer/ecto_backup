defmodule Mix.Tasks.EctoBackup.Gen.Release do
  @moduledoc """
  Mix task to generate shell scripts to run EctoBackup in a release environment.

  The following release files are created:

    * `rel/overlays/bin/backup.sh` - Script to perform backups of configured Ecto repositories.

    * `rel/overlays/bin/restore.sh` - Script to perform restores of configured Ecto repositories.

  These scripts will be included in your release by default. If you have a custom release name
  you can specify it with the `--release` option.

  ## Command Line Options

    * `--release RELEASE_NAME` - Specify the name of the release. If not specified, the default
      application name will be used.

    * `--overlay OVERLAY_DIR`  - Specify the overlays directory where the scripts will be created
      in a `bin` subdirectory. Defaults to `rel/overlays`.

  """
  @shortdoc "Generates release scripts for EctoBackup"

  use Mix.Task

  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: [release: :string, overlay: :string])
    overlay = opts[:overlay] || "rel/overlays"
    scripts_dir = Path.join(overlay, "bin")
    File.mkdir_p!(scripts_dir)

    backup_script_path = Path.join(scripts_dir, "backup")
    restore_script_path = Path.join(scripts_dir, "restore")

    context = %{
      app_name: opts[:release] || Mix.Project.config() |> Keyword.fetch!(:app)
    }

    File.write!(backup_script_path, backup_script_content(context))
    File.chmod!(backup_script_path, 0o755)

    File.write!(restore_script_path, restore_script_content(context))
    File.chmod!(restore_script_path, 0o755)

    Mix.shell().info([:green, "* creating ", :reset, backup_script_path])
    Mix.shell().info([:green, "* creating ", :reset, restore_script_path])
  end

  defp backup_script_content(context) do
    """
    #!/bin/sh
    set -eu

    cd -P -- "$(dirname -- "$0")"
    exec ./#{context.app_name} eval \"EctoBackup.Release.backup(\\"$*\\")\"
    """
  end

  defp restore_script_content(context) do
    """
    #!/bin/sh
    set -eu

    cd -P -- "$(dirname -- "$0")"
    exec ./#{context.app_name} eval \"EctoBackup.Release.restore(\\"$*\\")\"
    """
  end
end
