# GCP Dash

Small Bash tools for working with isolated Google Cloud profiles (plus one GPU status helper).

## Design Intent

- Primary use case: keep human GCP usage clean and predictable across projects/accounts.
- Secondary use case: let automation/agents run as the same human identity currently selected in the shell.
- Explicitly out of scope: service account impersonation workflows in these scripts.

## Why this exists

`gcloud` native configurations are useful, but these scripts add:

- Profile isolation by directory (`CLOUDSDK_CONFIG` per profile).
- Faster profile management (`list`, `copy`, `rename`, `remove`) with one consistent UI.
- Easy terminal pinning for workflows where one shell should stay on one project/account.

## Requirements

- Bash 4+
- Google Cloud CLI (`gcloud`) for auth/status operations
- Linux/WSL/macOS style shell environment

## Quick Start

Clone and install:

```bash
git clone <your-repo-url>
cd local
./deploy-bin
```

Install to a custom path:

```bash
./deploy-bin -b /some/other/bin
```

If needed, add `~/bin` to `PATH`:

```bash
export PATH="$HOME/bin:$PATH"
```

Authenticate and pin current shell:

```bash
source ~/bin/gcp-auth c1-stage c1-stage-project admin-c1@company1.com
```

Switch later without re-auth:

```bash
source ~/bin/gcp-auth my-profile
```

Check current shell context:

```bash
gcp-status
```

## `gcp-auth` behavior

Argument order:

- `source gcp-auth <profile_number_or_name> [project_id] [account_email]`
- If no args are provided, `gcp-auth` lists profiles and exits.
- Selector can be profile name or list index (for example `source gcp-auth 3`).

Input safety:

- If the second argument looks like an email and no third argument is given, it is treated as `account_email` (not `project_id`).
- If `project_id`/`account_email` look swapped, `gcp-auth` auto-corrects and prints a warning.
- If effective project is missing or invalid, `gcp-auth` fails before auth/ADC login.

Update flow for existing profiles:

- No account/project change: switch only, no auth steps.
- Project-only change:
  - always updates `gcloud config set project`
  - if ADC exists for that profile, runs `gcloud auth application-default set-quota-project`
  - if ADC does not exist, runs `gcloud auth application-default login`
- Account change (or new profile): runs full `gcloud auth login` + `gcloud auth application-default login`.

## Commands

Run `gcp-` to see all GCP helper commands:

```bash
gcp-
```

Included scripts:

- `gcp-`: Show all GCP helper commands.
- `gcp-auth`: Authenticate/switch profile for current shell (must be sourced).
- `gcp-status`: Show active shell GCP context and auth state.
- `gcp-ls`: List profiles.
- `gcp-cp-profile`: Copy profile by number or name to a new name.
- `gcp-nc`: Rename profile by number or name.
- `gcp-rm-profile`: Delete one or more profiles by number.
- `gpu-status`: Show GPU status across configured hosts.

All profile-list output uses:

- `*n) name, account, project` for active profile, otherwise ` n) name, account, project`

Machine-readable list output:

```bash
gcp-ls -j
# same as: gcp-ls --json
```

## Profile Storage

By default profiles are stored per-user:

- `${XDG_CONFIG_HOME:-~/.config}/gcpdash/<profile>`

Override profile root if desired:

```bash
export GCP_CFG_BASE="$PWD/.gcpdash"
```

## Safety Notes

- `gcp-rm-profile` deletes profile directories recursively and permanently.
- `gcp-nc` and `gcp-cp-profile` operate on directory names, not cloud-side resources.
- No service account impersonation behavior is implemented in these helpers.
- Prefer testing with a temporary `GCP_CFG_BASE` before bulk changes.
- Non-interactive profile mutations require `-y|--yes`.

Examples:

```bash
gcp-cp-profile -y 2 my-copy
gcp-nc -y 3 my-renamed-profile
gcp-cp-profile -y c1-stage c1-stage-copy
gcp-nc -y c1-stage-copy c1-stage-sandbox
gcp-rm-profile -y 1,4
```

## Testing

Run lightweight smoke tests:

```bash
./tests/test-gcp-helpers.sh
```

Tests cover list/json/copy/rename flows, profile-selection behavior in `gcp-auth`, and non-interactive safety behavior.

GitHub Actions CI runs:

- shellcheck
- bash syntax checks
- smoke tests

## License

MIT. See `LICENSE`.
