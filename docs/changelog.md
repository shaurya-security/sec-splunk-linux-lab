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
