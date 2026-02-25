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

Re-auth an existing profile when needed (standalone command, not sourced):

```bash
gcp-reauth -y my-profile
```

Check current shell context:

```bash
gcp-status
```

Verify shell/profile/token alignment (automation-friendly exit code):

```bash
gcp-status -v
```

## `gcp-auth` behavior

Argument order:

- `source gcp-auth [--no-browser|--no-broser] <profile_number_or_name> [project_id] [account_email]`
- If no args are provided, `gcp-auth` lists profiles and exits.
- Selector can be profile name or list index (for example `source gcp-auth 3`).
- `--no-browser` disables browser auto-launch for auth flows (also accepts typo alias `--no-broser`).
- On WSL, no-browser mode is auto-enabled when `WSL_INTEROP` or `WSL_DISTRO_NAME` is set.

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
- Account change (or new profile): runs one flow with `gcloud auth login --update-adc`.

## `gcp-reauth` behavior

- `gcp-reauth` is a regular executable and does **not** need `source`.
- Argument order:
  - `gcp-reauth [-y|--yes] [--no-browser|--no-broser] [profile_number_or_name] [account_email]`
- If profile is omitted, it uses the profile from `CLOUDSDK_CONFIG` when available.
- Re-auth flow for the selected profile:
  - runs `gcloud auth login --update-adc`
  - then runs `gcloud auth application-default set-quota-project <saved_project>`
- If browser login returns a different account than expected, `gcp-reauth` fails with a mismatch error and guidance.
- In non-interactive mode, re-auth requires `-y|--yes`.

## `gcp-status --verify` behavior

- `gcp-status -v` (or `--verify`) performs strict checks and exits non-zero on failure.
- Verifies project env pins (`GOOGLE_CLOUD_PROJECT`, `GCLOUD_PROJECT`, `CLOUDSDK_CORE_PROJECT`) are set and aligned.
- Verifies `gcloud` account/project match the active profile metadata under `CLOUDSDK_CONFIG`.
- Verifies user token and ADC token refresh via:
  - `gcloud auth print-access-token`
  - `gcloud auth application-default print-access-token`

## Commands

Run `gcp-` to see all GCP helper commands:

```bash
gcp-
```

Included scripts:

- `gcp-`: Show all GCP helper commands.
- `gcp-auth`: Authenticate/switch profile for current shell (must be sourced).
- `gcp-reauth`: Re-authenticate an existing profile (standalone command).
- `gcp-status`: Show active shell GCP context and auth state.
- `gcp-ls`: List profiles.
- `gcp-cp-profile`: Copy profile by number or name to a new name.
- `gcp-nc`: Rename profile by number or name.
- `gcp-rm-profile`: Delete one or more profiles by number.

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
- Non-interactive re-auth requires `-y|--yes`.

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

Tests cover list/json/copy/rename flows, profile-selection behavior in `gcp-auth`, `gcp-reauth` flows, and non-interactive safety behavior.

GitHub Actions CI runs:

- shellcheck
- bash syntax checks
- smoke tests

## CI/CD Sync

On every push to `main` (including merged PRs), CI runs tests first. If tests are green, the workflow syncs `main` to:

- `origin/main`
- `public/main` (mirror remote)

Mirror configuration:

- Required secret: `PUBLIC_MIRROR_SSH_KEY` (SSH private key that can push to the mirror repo)
- Optional repository variable: `PUBLIC_MIRROR_URL` (defaults to `git@github.com:WmSadler/gcp-dash.git`)

## License

MIT. See `LICENSE`.
