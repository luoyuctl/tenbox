# Agent Data Tools

TenBox.app provides Agent data export/import, backup/restore, and health actions
without requiring Hermes/OpenClaw images to preinstall TenBox-specific scripts.

The macOS manager creates a temporary shared folder, then sends a short shell
command through qemu-guest-agent `guest-exec`. The command uses standard guest
tools such as `tar`, `gzip`, `systemctl`, `curl`, and `journalctl`.

## Profile package

The exported package is a gzip tar archive:

```text
<vm>-<agent>-profile.tar.gz
├── manifest.json
└── files.tar.gz
```

`manifest.json` contains:

- `format`: `tenbox-agent-profile`
- `format_version`: `2`
- `agent_type`: `hermes` or `openclaw`
- `export_scope`: `migration` or `backup`
- `archive`: `files.tar.gz`

`files.tar.gz` contains the Agent data directory relative to the guest home:

- Hermes: `.hermes`
- OpenClaw: `.openclaw`

Always excluded paths:

- Hermes: `.hermes/logs`, `.hermes/image_cache`, `.hermes/audio_cache`,
  `.hermes/cache`, `.hermes/hermes-agent`, `.hermes/bin`, `.hermes/gateway.pid`,
  `.hermes/gateway.lock`
- OpenClaw: `.openclaw/cache`, `.openclaw/.cache`, `.openclaw/workspace/.cache`,
  `.openclaw/logs`

Migration exports keep secrets, identity, session state, and config files so a
profile can move with the user's full Agent state. Only volatile logs, caches,
runtime lock files, and reinstallable binaries are skipped.

Import rejects packages whose `agent_type` does not match the selected Agent.
Before replacing existing data, it renames the current directory to
`*.pre-import-YYYYMMDDHHMMSS`.

## Backups

Manual backups are created by TenBox.app in:

```text
~/Library/Application Support/TenBox/AgentBackups/<vm-id>/<agent>/
```

Backups use the same profile package format. Retention is configurable per VM
and Agent; the default keeps the newest seven packages. Restore uses the package
selected in the backup list for the selected VM and Agent.

Host-managed backups use `export_scope: backup` and keep restorable user state
except volatile logs, caches, runtime lock files, and reinstallable binaries.
They are intended for recovery on the same host, not for sharing.

## Health actions

TenBox.app can run these actions while the VM is running:

- health status
- restart Agent
- reset Agent config
- export diagnostics

Restart and reset create a backup first, using the same host-managed backup
directory. Diagnostics are exported to the host backup directory through the
temporary shared folder.

## OpenClaw to Hermes migration

When both source and target VMs are running, TenBox.app can migrate OpenClaw
data into a Hermes VM without image-specific helper scripts:

1. Create a host-managed Hermes backup for the target VM.
2. Mount one runtime-only host shared folder into both VMs.
3. Export the source VM's `~/.openclaw` into that shared folder with full user
   state, including secrets, identity, browser profile, and OpenClaw config.
4. Extract it inside the Hermes VM and run the official Hermes CLI:

   ```sh
   hermes claw migrate --dry-run --source <shared>/.openclaw --preset full --migrate-secrets
   hermes claw migrate --source <shared>/.openclaw --preset full --migrate-secrets --skill-conflict skip --yes
   ```

The migration deliberately uses the `full` preset with `--migrate-secrets` so
Hermes can import every compatible secret and file category its official
OpenClaw migration flow supports.
