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
