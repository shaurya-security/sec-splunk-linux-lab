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
