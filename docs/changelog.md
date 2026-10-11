# Changelog

## 2026-10-09 — Architecture created

- docs/architecture.md created from a full project scan (version 1, 30 files).

## 2026-10-09 — Add endpoint instance ID outputs
### Added
- Added Terraform outputs for the Linux and Windows endpoint EC2 instance IDs.
### Validation
- `terraform -chdir=terraform/lab validate` — passed.

## 2026-10-09 — Add Linux and Windows forwarder endpoints
### Added
- Added Linux and Windows EC2 endpoint instances, endpoint IAM access, Universal Forwarder bootstrap/configuration, and instance ID outputs.
### Validation
- `terraform -chdir=terraform/lab fmt -check -recursive` — passed.
- `terraform -chdir=terraform/lab validate` — passed.

## 2026-10-09 — Standardize endpoint diagnostics and hostnames
### Changed
- Extended Linux bootstrap log scanning to include endpoint logs and added a matching PowerShell diagnostic utility for Windows.
- Standardized endpoint bootstrap failures on `[BOOTSTRAP ERROR]`, installed diagnostic helpers on each endpoint, and set the endpoint hostnames to `splunk-linux` and `splunk-windows`.
- Updated architecture notes for endpoint naming and diagnostic flows.
### Validation
- `terraform -chdir=terraform/lab fmt -check -recursive` — passed.
- `terraform -chdir=terraform/lab validate` — passed.
- `bash -n terraform/lab/userdata/userdata-logs.sh terraform/lab/userdata/linux-endpoint-bootstrap.sh.tpl terraform/lab/userdata/linux-endpoint.sh` — passed.

## 2026-10-09 — Architecture refreshed

- docs/architecture.md rebuilt from a full project scan (version 3, 31 files).

## 2026-10-09 — Add Sigma authentication detections
### Added
- Added Sigma event rules for Linux SSH authentication failures and Windows Security Event ID 4625.
- Added Linux and Windows correlation rules for repeated account failures and password spraying, with documented field/index mapping prerequisites and coverage limits.
- Updated architecture documentation with the Sigma rule location and deployment dependencies.
### Validation
- Parsed all six Sigma rule files with PyYAML.
- `git diff --check` — passed.

## 2026-10-10 — Architecture refreshed

- docs/architecture.md rebuilt from a full project scan (version 5, 38 files).

## 2026-10-10 — Make Linux bootstrap log scanning role-aware
### Fixed
- Scan only the log files expected for `splunk-server` or `linux-endpoint-01` instead of mixing both hosts' logs.
- Treat expected missing or unreadable logs as failures, preventing a false success when bootstrap logs are absent.
- Removed the obsolete `linux_bootstrap.log` expectation; added explicit role selection as a fallback.
### Validation
- `bash -n terraform/lab/userdata/userdata-logs.sh` — passed.
- `git diff --check` — passed.

## 2026-10-10 — Replace instances when staged userdata scripts change
### Changed
- Added local file hashes to the Splunk, Linux endpoint, and Windows endpoint user-data templates for the S3-downloaded scripts each instance consumes.
- User-data script edits now change rendered `user_data`, activating the existing `user_data_replace_on_change = true` behavior for affected instances only.
### Validation
- `terraform -chdir=terraform/lab fmt -check -recursive` — passed.
- `terraform -chdir=terraform/lab validate` — passed.
- `bash -n terraform/lab/userdata/userdata-logs.sh terraform/lab/userdata/linux-endpoint-bootstrap.sh.tpl` — passed.
- `git diff --check` — passed.

## 2026-10-10 — Report userdata execution progress
### Changed
- Added percentage checkpoints and terminal completion markers to Splunk, Linux endpoint, and Windows endpoint bootstrap logs.
- Updated both diagnostic helpers to show each log's latest progress, completion/failure state, and active or possibly stalled status.
### Validation
- `terraform -chdir=terraform/lab fmt -check -recursive` — passed.
- `terraform -chdir=terraform/lab validate` — passed.
- `bash -n terraform/lab/userdata/bootstrap.sh.tpl terraform/lab/userdata/splunk-install.sh terraform/lab/userdata/linux-endpoint-bootstrap.sh.tpl terraform/lab/userdata/linux-endpoint.sh terraform/lab/userdata/userdata-logs.sh` — passed.
- `git diff --check` — passed.
- PowerShell validation was unavailable because `pwsh` is not installed in this environment.

## 2026-10-10 — Architecture refreshed

- docs/architecture.md rebuilt from a full project scan (version 9, 38 files).

## 2026-10-10 — Trust completion markers in userdata summary
### Fixed
- Report overall `COMPLETED` when all expected log files contain completion markers, even if systemd still reports `cloud-final` as active.
- Count completed and pending logs so an active cloud-init service does not override completed user-data stages.
### Validation
- `bash -n terraform/lab/userdata/userdata-logs.sh` — passed.
- `git diff --check` — passed.

## 2026-10-10 — Align Linux endpoint collection with auditd
### Changed
- Configure the Linux endpoint Universal Forwarder to monitor `/var/log/audit/audit.log`, matching the Splunk host's auditd source while retaining the endpoint's `linux_endpoint` index.
- Enable auditd and grant the forwarder rotation-safe read access through the `splunk-audit` group and a systemd supplementary-group override.
- Update the Linux Sigma event rule and field-mapping guidance for auditd `USER_AUTH` / `USER_LOGIN` failure records.
### Validation
- `terraform -chdir=terraform/lab fmt -check -recursive` — passed.
- `terraform -chdir=terraform/lab validate` — passed.
- `bash -n terraform/lab/userdata/linux-endpoint.sh` — passed.
- Parsed `detections/sigma/linux/linux_ssh_failed_auth.yml` with PyYAML — passed.
- `git diff --check` — passed.

## 2026-10-10 — Resolve Windows Universal Forwarder install path
### Fixed
- Discover the Universal Forwarder install directory from Windows uninstall registry metadata and common paths, then verify `bin\\splunk.exe` before writing app configuration.
- Report an explicit bootstrap error if MSI reports success but the executable cannot be found.
### Validation
- `terraform -chdir=terraform/lab fmt -check -recursive` — passed.
- `terraform -chdir=terraform/lab validate` — passed.
- `git diff --check` — passed.
- PowerShell syntax validation was unavailable; neither `pwsh` nor `powershell` is installed in this environment.

## 2026-10-10 — Install AWS CLI in Windows bootstrap when absent
### Fixed
- Download and install AWS CLI v2 from the official AWS MSI when it is missing, verify its Authenticode signature, and confirm `aws.exe` exists before S3 bootstrap downloads.
### Validation
- `terraform -chdir=terraform/lab fmt -check -recursive` — passed.
- `terraform -chdir=terraform/lab validate` — passed.
- `git diff --check` — passed.
- PowerShell syntax validation was unavailable; neither `pwsh` nor `powershell` is installed in this environment.

## 2026-10-10 — Centralize Windows endpoint bootstrap assets
### Changed
- Create `C:\\Soc-Lab` with `config`, `logs`, and `packages` subdirectories and configure the PowerShell profile to start there.
- Stage Windows bootstrap scripts, diagnostics helper, logs, and installer packages in the SOC-Lab directory; store authored forwarder configs there before copying them to the installed Splunk app directory.
- Update the Windows diagnostics helper to read logs from `C:\\Soc-Lab\\logs`.
### Validation
- `terraform -chdir=terraform/lab fmt -check -recursive` — passed.
- `terraform -chdir=terraform/lab validate` — passed.
- `git diff --check` — passed.
- PowerShell syntax validation was unavailable; neither `pwsh` nor `powershell` is installed in this environment.

## 2026-10-10 — Improve diagnostics presentation and document the project
### Changed
- Added terminal-aware colors, clearer status sections, and progress bars to the Linux and Windows userdata log helpers.
- Replaced the title-only README with project setup, deployment, operations, Sigma, and lifecycle guidance.
- Updated architecture notes to describe the README and Terraform backend version requirement.
### Validation
- `terraform -chdir=terraform/lab fmt -check -recursive` — passed.
- `terraform -chdir=terraform/lab validate` — passed.
- `bash -n terraform/lab/userdata/userdata-logs.sh` — passed.
- `git diff --check` — passed.
- PowerShell syntax validation was unavailable; neither `pwsh` nor `powershell` is installed in this environment.

## 2026-10-10 — Improve log helper presentation and document the project
### Changed
- Added terminal-aware colors, clearer status sections, and progress bars to the Linux and Windows userdata log helpers.
- Replaced the title-only README with project setup, deployment, operations, Sigma, and lifecycle guidance.
- Updated architecture notes for the README and lab Terraform backend version requirement.
### Validation
- `terraform -chdir=terraform/lab fmt -check -recursive` — passed.
- `terraform -chdir=terraform/lab validate` — passed.
- `bash -n terraform/lab/userdata/userdata-logs.sh` — passed.
- `git diff --check` — passed.
- PowerShell syntax validation was unavailable; neither `pwsh` nor `powershell` is installed in this environment.

## 2026-10-10 — Document Windows XML event search
### Changed
- Explain that Windows Event ID 4625 is currently present in raw XML, not extracted as `EventCode`, and document a raw XML search plus inline `rex` extraction example.
- Clarify that the repository's Sigma YAML rules are not automatically converted or run in Splunk.
### Validation
- `git diff --check` — passed.

## 2026-10-11 — Add Splunk add-ons and standardize Sigma rules
### Added
- Install and verify `Splunk_TA_windows` and `Splunk_TA_nix` from the userdata bucket `apps/` prefix in `splunk-install.sh`, with `btool` checks for `linux_audit` and `XmlWinEventLog` and an `Add-ons` line in `splunk-info.txt`. Missing add-ons log a warning and do not fail the bootstrap.
- Added `detections/sigma/pipelines/lab_splunk.yml` to scope rules to the lab indexes/sources and map `EventID` to `EventCode` and `Computer` to `host`.
- Documented post-deployment field-check searches and `sigma-cli` conversion in `detections/sigma/README.md`.
### Changed
- Standardized all six Sigma rules to Sigma/SigmaHQ conventions: logsource-prefixed file names (`lnx_auditd_*`, `win_security_*`, `corr_*`), 4-space indentation, hyphenated ATT&CK tactic tags, `modified` dates, "Detects ..." descriptions, and ATT&CK references moved to tags.
- Linux rules now use native auditd fields (`type`, `exe`, `res`, `acct`, `addr`) instead of ad-hoc `message`, `SourceIp`, and `User`; Windows rules use `Computer` instead of `ComputerName`. Event rules carry `attack.t1110`; correlation rules carry the specific sub-technique.
- The Linux event rule now requires `exe` ending in `/sshd`; previously it matched any failed `USER_AUTH`/`USER_LOGIN` record, including sudo, su, and console logins.
- Linux rules now cover both `linux_endpoint` and `linux_audit` (the Splunk host's own auditd).
- Updated README guidance: Windows `EventCode` is extracted once `Splunk_TA_windows` is installed.
### Notes
- Changing `splunk-install.sh` replaces the Splunk instance on the next apply; indexed data is lost with it.
### Validation
- `bash -n terraform/lab/userdata/splunk-install.sh` — passed.
- Add-on install and `btool` check logic exercised with stub packages and a stub `splunk` binary (add-ons present, partly loaded, and absent) — behaved as intended.
- Parsed all rule and pipeline files with PyYAML and checked them against the Sigma rule and correlation rule structure.
- `sigma check` / `sigma convert` and Terraform validation were not run: PyPI access was blocked and Terraform is not installed in this environment.

## 2026-10-11 — Sigma-to-Splunk deployment skeleton
### Added
- `detections/generated/*.spl`: six SPL files (2 event, 4 correlation). Hand-authored; NOT yet verified against `sigma-cli`/`pysigma-backend-splunk`
(PyPI unreachable in the authoring environment).
- `detections/sigma/deployment.yml`: per-rule schedule (`*/1`), lookback (-5m/-10m), trigger, severity; email disabled with placeholder recipient;
`alert.track=1`.
- `tools/deploy_sigma_searches.py`: idempotent REST upserter (dry-run default, loopback-only, password from SSM/env, searches created disabled unless
`--enable`, add-on and field preflight, JSON report without credentials).
- `tools/release.sh`: package, upload to S3, run on the Splunk host via SSM. No inbound 8089.
- `tests/test_deploy.py` (mock Splunk REST; 6 tests), `requirements-dev.txt` (unpinned, see below).
### Changed
- `lab_splunk.yml` pipeline maps Windows `IpAddress` -> `src_ip`.
### Removed
- `terraform/lab/.github/` and `terraform/lab/.checkov.yaml`. The project now has no active CI.
### Open items
- Pin and run the converter, diff its output against `detections/generated/`.
- Verify against a real Splunk 10.4 instance (REST encoding, namespace) and field extraction; SMTP/recipient before enabling email.
### Validation
- `python3 -I -m unittest discover -s tests` — passed (mock server only; no real Splunk or Terraform run).
