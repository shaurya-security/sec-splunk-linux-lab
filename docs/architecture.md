# Project Architecture

## Project
- Name: `sec-splunk-linux-lab`
- Purpose: Terraform-managed AWS lab running Splunk Enterprise, Linux and Windows Universal Forwarder endpoints, and experimental Sigma authentication detections.
- Root: `.`; Terraform configurations are under `terraform/`.

## Directory Structure

```text
.
├── README.md
├── docs/
│   └── architecture.md
├── detections/
│   └── sigma/
│       ├── linux/              # Linux authentication event rules
│       ├── windows/            # Windows authentication event rules
│       └── correlation/        # Brute-force and password-spray rules
└── terraform/
    ├── bootstrap/              # S3 bucket for Terraform state
    └── lab/
        ├── .github/workflows/  # Terraform CI workflow
        └── userdata/           # Instance bootstrap templates and scripts
```

## Architecture

### Infrastructure
- `terraform/bootstrap/` configures the S3 bucket used for lab Terraform state.
- `terraform/lab/` provisions the AWS network, IAM and SSM resources, bootstrap-script objects, and Splunk, Linux endpoint, and Windows endpoint EC2 instances.
- The lab expects a pre-existing S3 bucket for bootstrap scripts, Splunk and Universal Forwarder packages, and optional Splunk apps.

### Application
- `terraform/lab/userdata/` contains instance bootstrap templates and OS-specific scripts for installing and configuring Splunk Enterprise and Universal Forwarders.
- The Splunk host and Linux endpoint collect `/var/log/audit/audit.log` as `linux_audit`, using separate indexes (`linux_audit` and `linux_endpoint`); Windows forwards Security events to `windows_endpoint`.
- User-data templates track script hashes; changes can replace the associated EC2 instance.
- Windows bootstrap artifacts, logs, and authored forwarder configs are centralized under `C:\Soc-Lab`; active Splunk app configs are copied into the discovered Universal Forwarder install directory.
- Windows forwarder setup resolves the MSI install directory from registry metadata/common paths and verifies `splunk.exe` before configuring inputs.
- Linux log diagnostics treat per-log completion markers as authoritative; `cloud-final` activity is used only to classify logs without a terminal marker.

### Networking
- The lab creates a VPC, one public subnet in `ap-south-1a`, an internet gateway, and a default internet route.
- All three instances receive public IPs and unrestricted outbound traffic.
- Splunk Web ingress on port 8000 is restricted to the public IP fetched during Terraform execution. Forwarding on port 9997 is allowed from the endpoint security group.
- Endpoint security groups have no inbound rules. SSH and Splunk management port 8089 are not exposed; Session Manager is the intended access path.

### Storage
- `terraform/bootstrap/` uses local Terraform state; the lab uses an encrypted S3 backend with lockfile support.
- The bootstrap state bucket enables AES256 encryption and blocks public access. Its force-destroy setting is hard-coded; some declared bucket options are not applied.
- EC2 root volumes are encrypted gp3 EBS volumes.
- The lab's pre-existing S3 bucket stores uploaded bootstrap scripts, packages, and optional Splunk apps.
- The Splunk admin password is stored as an SSM SecureString and is also present in Terraform state.

### IAM / Security
- Separate instance roles provide Session Manager access to the Splunk host and endpoints.
- The Splunk role can read bootstrap objects and its password parameter. Endpoint roles can read bootstrap scripts and Universal Forwarder packages, but not the password parameter.
- EC2 metadata access requires IMDSv2.
- Security groups restrict inbound access to Splunk Web from the operator's IP and forwarding traffic from the endpoint security group.

## Important Files

| File | Purpose |
|------|---------|
| `terraform/bootstrap/backend.tf` | Configures local state for the state-bucket bootstrap. |
| `terraform/bootstrap/s3.tf` | Defines the state bucket, encryption, and public-access block. |
| `terraform/bootstrap/variables.tf` | Declares bootstrap inputs and defaults. |
| `terraform/lab/main.tf` | Declares lab providers and AWS region. |
| `terraform/lab/backend.tf` | Configures the lab S3 state backend. |
| `terraform/lab/compute.tf` | Defines EC2 instances and their bootstrap inputs. |
| `terraform/lab/vpc.tf` | Defines the VPC, subnet, routes, and security groups. |
| `terraform/lab/iam.tf` | Defines instance roles, policies, and profiles. |
| `terraform/lab/s3.tf` | Uploads bootstrap scripts to the userdata bucket. |
| `terraform/lab/ssm.tf` | Generates and stores the Splunk admin password in SSM Parameter Store. |
| `terraform/lab/userdata/` | Contains instance bootstrap templates, setup scripts, and log helpers. |
| `terraform/lab/userdata/windows-endpoint-bootstrap.ps1.tpl` and `windows-endpoint.sh` | Set up `C:\Soc-Lab`, stage Windows bootstrap assets, and install Universal Forwarder configs. |
| `terraform/lab/.github/workflows/terraform.yml` | Defines Terraform and Checkov CI checks. |
| `detections/sigma/` | Contains Linux and Windows authentication rules and correlation rules. |
| `detections/sigma/README.md` | Documents index scoping, field mapping, and detection validation limits. |

## Dependencies
- Terraform 1.5 or later is required by the bootstrap configuration.
- AWS provider `~> 6.0`; the lab also uses `time ~> 0.11` and `random ~> 3.6`.
- AWS account permissions for Terraform-managed EC2, VPC, IAM, S3, and SSM resources.
- The userdata bucket and required Splunk and Universal Forwarder package objects must exist and be accessible.
- CI references GitHub Actions, the Terraform setup action, and Checkov.

## Configuration
- Terraform inputs and defaults are in `terraform/bootstrap/variables.tf` and `terraform/lab/variables.tf`; derived names are in `terraform/lab/locals.tf`.
- The lab region and backend settings are in `terraform/lab/main.tf` and `terraform/lab/backend.tf`.
- The public IP used for Splunk Web ingress is fetched dynamically in `terraform/lab/data.tf`.
- Keep credentials and sensitive overrides out of version control. `.gitignore` excludes Terraform state and tfvars files.
- Sigma deployment must scope Linux detections to `linux_endpoint` and Windows detections to `windows_endpoint`; confirm and normalize fields before using correlations.

## Runtime Flow

```text
EC2 boot
  ├── Splunk host: bootstrap template → S3 setup scripts → Splunk Enterprise
  ├── Linux endpoint: bootstrap template → Linux setup → Universal Forwarder
  └── Windows endpoint: PowerShell bootstrap → Universal Forwarder

Linux and Windows Universal Forwarders ── TCP 9997 ──> Splunk Enterprise
Operator ── HTTPS 8000 ──> Splunk Web
Operator ── AWS Systems Manager Session Manager ──> EC2 instances
Authentication events ──> linux_endpoint / windows_endpoint indexes ──> Sigma detections
```

## Deployment Flow

```text
terraform/bootstrap/
  └── terraform init / apply → state S3 bucket

terraform/lab/
  └── configure backend → terraform init → plan / apply
        ├── create network, IAM, SSM parameter, and S3 script objects
        └── create EC2 instances and run their bootstrap flows

GitHub Actions runs Terraform and Checkov checks.
```

## External Services
- AWS EC2, VPC, IAM, S3, Systems Manager, and SSM Parameter Store.
- `ipv4.icanhazip.com` supplies the public client IP used for Splunk Web ingress.
- GitHub Actions, the Terraform setup action, and Checkov are referenced by CI.
- Instance bootstrap accesses external sources for OS packages and Starship.
- Windows bootstrap downloads the AWS CLI v2 MSI from `awscli.amazonaws.com` if the AMI does not include it.

## Important Constraints
- This is a lab network: instances use one public subnet and unrestricted outbound egress.
- Terraform uploads scripts but does not create the userdata bucket or provide Splunk and Universal Forwarder package artifacts.
- The admin password is stored in Terraform state as well as SSM; protect state access.
- AMI IDs and package versions are pinned and may need maintenance.
- Changes to hashed user-data scripts can replace EC2 instances; root volumes are deleted on termination.
- The Windows bootstrap installs AWS CLI v2 from the official signed AWS MSI when it is absent from the AMI.
- Sigma correlations require verified source-IP, account, and host fields. Windows failed-logon auditing must be enabled.

## Current State
- The repository contains a state-bucket bootstrap and an AWS Splunk lab Terraform configuration.
- The lab defines a Splunk server, Linux and Windows forwarding endpoints, Session Manager access, and S3-based bootstrap.
- The root README contains only the project title.

## Known Issues
- The GitHub Actions workflow is documented as using `terraform-lab` as its working directory and Checkov target, while the Terraform configuration is under `terraform/lab`; CI paths may need correction.
- `terraform/bootstrap/variables.tf` declares versioning, force-destroy, and KMS options, but `terraform/bootstrap/s3.tf` hard-codes force-destroy and AES256 encryption and does not configure versioning.
- The lab expects a pre-existing userdata bucket and package artifacts; these are not provisioned by the lab Terraform configuration.
- Sigma correlations require verified field extraction and backend support for Sigma correlation rules; Windows failed-logon auditing must also be enabled.

## Metadata

- Architecture version: 14
- Last updated: 2026-10-10T23:28:12+05:30
- Last full scan: 2026-10-10T01:41:27+05:30
- Files represented: 40
- Last updated by: ai
