# Project Architecture

## Project
- Name: `sec-splunk-linux-lab`
- Purpose: Terraform-managed AWS lab for Splunk Enterprise, Linux and Windows Universal Forwarders, and brute-force detections.
- Root: `.`

## Directory Structure

```text
.
├── README.md
├── docs/
│   └── architecture.md
├── detections/
│   ├── deployment.yml
│   ├── README.md
│   └── spl/                 # Linux SSH and Windows logon searches
├── terraform/
│   ├── bootstrap/           # S3 bucket for lab Terraform state
│   └── lab/
│       └── userdata/        # Instance bootstrap templates and scripts
├── tests/                   # Deployment-tool tests
└── tools/                   # Saved-search deploy and release utilities
```

## Architecture

### Infrastructure
- `terraform/bootstrap/` creates the S3 bucket used as the lab's remote Terraform state backend.
- `terraform/lab/` provisions the VPC, IAM and SSM resources, uploads bootstrap scripts, and creates Splunk, Linux endpoint, and Windows endpoint EC2 instances.
- The lab relies on a pre-existing userdata S3 bucket for software packages and optional Splunk add-ons.

### Application
- `terraform/lab/userdata/` contains templates and scripts that install and configure Splunk Enterprise and the Linux and Windows Universal Forwarders.
- The Linux endpoint forwards auditd events to the `linux_endpoint` index with `linux_audit` sourcetype. The Windows endpoint forwards Application, System, and Security events to `windows_endpoint`.
- Splunk-host add-ons provide search-time field extractions for the detections; missing add-ons generate warnings during bootstrap.
- `detections/spl/` holds two SPL brute-force searches. `detections/deployment.yml` supplies their saved-search scheduling and alert settings.
- `tools/deploy_searches.py` validates and deploys saved searches through Splunk's local REST API; `tools/release.sh` runs deployment on the Splunk host through SSM.

### Networking
- The lab creates a VPC with one public subnet in `ap-south-1a`, an internet gateway, and a default internet route.
- All three instances have public IPs and unrestricted outbound traffic.
- Splunk Web on TCP 8000 is restricted to the operator IP detected during Terraform execution. TCP 9997 ingress is limited to the endpoint security group.
- SSH, RDP, and Splunk management port 8089 are not exposed; Session Manager is the intended access path.

### Storage
- Bootstrap Terraform uses local state; lab Terraform uses an encrypted S3 backend with lockfile support.
- EC2 root volumes are encrypted gp3 volumes and are deleted when their instances terminate.
- The pre-existing userdata bucket holds uploaded scripts, required Splunk and Universal Forwarder packages, and optional add-ons.
- Terraform generates the Splunk admin password and stores it as an SSM SecureString; it is also present in Terraform state.

### IAM / Security
- Separate instance roles provide Session Manager access to Splunk and the endpoints.
- The Splunk role can read userdata objects and its password parameter. Endpoint roles can read bootstrap scripts and Universal Forwarder packages, but not the password parameter.
- EC2 metadata access requires IMDSv2.
- The state bucket blocks public access and uses server-side encryption. Its Terraform configuration currently hard-codes `force_destroy = true`.

## Important Files

| File | Purpose |
|------|---------|
| `README.md` | Project overview, prerequisites, deployment, operations, and lab warnings. |
| `terraform/bootstrap/backend.tf` | Configures local state for the state-bucket bootstrap. |
| `terraform/bootstrap/s3.tf` | Defines the state bucket, encryption, and public-access block. |
| `terraform/lab/main.tf` | Declares lab providers and AWS region. |
| `terraform/lab/backend.tf` | Configures the lab's S3 state backend. |
| `terraform/lab/compute.tf` | Defines EC2 instances and their bootstrap inputs. |
| `terraform/lab/vpc.tf` | Defines the VPC, subnet, routes, and security groups. |
| `terraform/lab/iam.tf` | Defines instance roles, policies, and profiles. |
| `terraform/lab/s3.tf` | Uploads bootstrap scripts to the userdata bucket. |
| `terraform/lab/ssm.tf` | Generates and stores the Splunk admin password in SSM Parameter Store. |
| `terraform/lab/userdata/` | Contains instance bootstrap templates, setup scripts, and diagnostic helpers. |
| `detections/spl/` | Linux SSH and Windows failed-logon SPL searches. |
| `detections/deployment.yml` | Saved-search schedule and alert settings. |
| `detections/README.md` | Detection data requirements, field checks, deployment, and limits. |
| `tools/deploy_searches.py` | Validates and deploys saved searches through Splunk REST. |
| `tools/release.sh` | Runs saved-search deployment on the Splunk host through SSM. |
| `tests/test_deploy.py` | Tests for the deployment utility. |

## Dependencies
- Terraform 1.5+ for bootstrap; Terraform 1.10+ for the lab S3 backend lockfile.
- AWS provider `~> 6.0`; lab also uses `time ~> 0.11` and `random ~> 3.6`.
- AWS credentials and permissions for the Terraform-managed EC2, VPC, IAM, S3, and Systems Manager resources.
- A pre-existing userdata bucket with the Splunk Enterprise and Universal Forwarder packages and, for detection field extractions, the Splunk Windows and Unix/Linux add-ons.
- Python 3 for `tools/deploy_searches.py`; AWS CLI and SSM access for the release path.

## Configuration
- Terraform inputs and defaults are in `terraform/bootstrap/variables.tf` and `terraform/lab/variables.tf`; derived names are in `terraform/lab/locals.tf`.
- The lab region and backend are configured in `terraform/lab/main.tf` and `terraform/lab/backend.tf`.
- `terraform/lab/data.tf` fetches the operator's public IP for Splunk Web ingress.
- Detection schedule and alert settings are in `detections/deployment.yml`.
- Keep credentials and sensitive overrides out of version control; the admin password is stored in Terraform state as well as SSM.

## Runtime Flow

```text
EC2 boot
  ├── Splunk host: bootstrap template → S3 scripts/packages → Splunk Enterprise and add-ons
  ├── Linux endpoint: bootstrap template → setup → Universal Forwarder and auditd inputs
  └── Windows endpoint: PowerShell bootstrap → setup → Universal Forwarder and event channels

Linux and Windows Universal Forwarders ── TCP 9997 ──> Splunk Enterprise
Splunk Enterprise ── indexes and extracts fields ──> SPL saved searches
Operator ── HTTPS 8000 ──> Splunk Web
Operator ── AWS Systems Manager Session Manager ──> EC2 instances
```

## Deployment Flow

```text
terraform/bootstrap/
  └── init / plan / apply → state S3 bucket

terraform/lab/
  └── configure backend → init / plan / apply
        ├── create network, IAM, SSM parameter, and S3 script objects
        └── create EC2 instances and run bootstrap flows

tools/release.sh
  └── SSM to Splunk host → deploy saved searches disabled by default
        └── review, then explicitly enable as needed
```

## External Services
- AWS EC2, VPC, IAM, S3, Systems Manager, and SSM Parameter Store.
- `ipv4.icanhazip.com` supplies the public client IP used for Splunk Web ingress.
- AWS CLI v2 may be downloaded from `awscli.amazonaws.com` by Windows bootstrap when it is absent from the AMI.
- OS package repositories and the pre-existing userdata bucket supply bootstrap dependencies and Splunk packages.

## Important Constraints
- This is a lab network: instances occupy one public subnet and have unrestricted outbound access.
- Terraform uploads scripts but does not create the userdata bucket or supply Splunk, Universal Forwarder, or add-on packages.
- Changes to hashed user-data scripts can replace instances; root volumes are deleted on termination.
- Protect Terraform state, which contains the generated Splunk admin password.
- The detections depend on add-on field extractions and suitable event data; verify fields before enabling alerts.
- Bootstrap bucket force-destroy can remove its objects, including lab state.

## Current State
- The repository contains bootstrap and lab Terraform configurations, Linux and Windows endpoint setup, two SPL detections, and saved-search deployment utilities.
- The lab README documents prerequisites, deployment, access, operations, and lifecycle warnings.
- No CI workflow is present in the scanned project tree.

## Known Issues
- `terraform/bootstrap/variables.tf` declares bucket options that `terraform/bootstrap/s3.tf` does not apply; the S3 configuration hard-codes force-destroy and AES256 encryption.
- The lab requires a pre-existing userdata bucket and package artifacts.
- Missing Splunk add-ons do not fail bootstrap, but required extracted fields may be empty.
- The searches have not been confirmed against live events; validate data and field extraction before enabling alerts.

## Metadata

- Architecture version: 17
- Last updated: 2026-10-12T00:09:07+05:30
- Last full scan: 2026-10-12T00:09:07+05:30
- Files represented: 36
- Last updated by: ai
