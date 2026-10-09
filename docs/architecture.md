# Project Architecture

## Project
- Name: `sec-splunk-linux-lab`
- Purpose: Terraform-managed AWS lab running Splunk Enterprise with Linux and Windows Universal Forwarder endpoints and experimental Sigma authentication detections.
- Root: `.`; state-bucket bootstrap and lab configurations are under `terraform/`.

## Directory Structure

```text
.
├── README.md
├── detections/
│   └── sigma/
│       ├── linux/              # Linux authentication event rules
│       ├── windows/            # Windows authentication event rules
│       └── correlation/        # Brute-force and password-spray rules
├── docs/
│   └── architecture.md
└── terraform/
    ├── bootstrap/              # S3 bucket for Terraform state
    └── lab/
        ├── .github/workflows/  # Terraform CI workflow
        └── userdata/           # Instance bootstrap templates and setup scripts
```

## Architecture

### Infrastructure
- `terraform/bootstrap/` configures an S3 bucket for Terraform state.
- `terraform/lab/` provisions a VPC, IAM and SSM resources, S3 script objects, and three EC2 instances: Splunk, Linux endpoint, and Windows endpoint.
- The lab uses a pre-existing S3 bucket for bootstrap scripts, Splunk and Universal Forwarder packages, and optional Splunk apps.

### Application
- The Splunk host installs Splunk Enterprise using scripts in `terraform/lab/userdata/`.
- Linux and Windows endpoint scripts install and configure Universal Forwarders to send telemetry to Splunk.
- Linux setup and endpoint scripts configure the host and collect authentication logs; Windows endpoint scripts configure Security event forwarding.
- Experimental Sigma event and correlation rules in `detections/sigma/` cover Linux SSH authentication failures and Windows failed logons.

### Networking
- The lab creates one VPC and public subnet in `ap-south-1a`, with an internet gateway and default internet route.
- All three instances receive public IPs and unrestricted outbound traffic.
- Splunk Web ingress on port 8000 is limited to the public IP fetched during Terraform execution. Forwarding on port 9997 is allowed from the endpoint security group.
- Endpoint security groups have no inbound rules. SSH and Splunk management port 8089 are not exposed; instance access is intended through Session Manager.

### Storage
- Bootstrap Terraform state is local to `terraform/bootstrap/`; the lab uses an encrypted S3 backend with lockfile support.
- The state bucket configuration applies AES256 server-side encryption and blocks public access.
- EC2 root volumes are encrypted gp3 EBS volumes.
- The pre-existing lab S3 bucket stores uploaded bootstrap scripts, packages, and optional Splunk apps.
- The Splunk admin password is stored as an SSM SecureString and is also present in Terraform state.

### IAM / Security
- Separate instance roles provide SSM access to the Splunk host and endpoints.
- The Splunk role can read bootstrap objects and its password parameter. Endpoint roles can read bootstrap scripts and Universal Forwarder packages, but not the password parameter.
- EC2 metadata access requires IMDSv2.
- Security groups limit inbound access to the Splunk Web client IP and endpoint-to-Splunk forwarding traffic.

## Important Files

| File | Purpose |
|------|---------|
| `terraform/bootstrap/backend.tf` | Configures local state for the state-bucket bootstrap. |
| `terraform/bootstrap/s3.tf` | Defines the state bucket, encryption, and public-access block. |
| `terraform/bootstrap/variables.tf` | Declares bootstrap inputs and defaults. |
| `terraform/lab/main.tf` | Declares lab providers and AWS region. |
| `terraform/lab/backend.tf` | Configures the lab S3 state backend. |
| `terraform/lab/compute.tf` | Defines the three EC2 instances and their bootstrap inputs. |
| `terraform/lab/vpc.tf` | Defines the VPC, public subnet, routes, and security groups. |
| `terraform/lab/iam.tf` | Defines instance roles, policies, and profiles. |
| `terraform/lab/s3.tf` | Uploads bootstrap scripts to the userdata bucket. |
| `terraform/lab/ssm.tf` | Generates and stores the Splunk admin password in SSM Parameter Store. |
| `terraform/lab/locals.tf` | Defines derived resource names, hostnames, and password parameter path. |
| `terraform/lab/userdata/` | Contains OS-specific bootstrap templates and setup scripts. |
| `terraform/lab/.github/workflows/terraform.yml` | Defines Terraform formatting, validation, and Checkov CI steps. |
| `detections/sigma/` | Contains Linux and Windows authentication rules and correlation rules. |
| `detections/sigma/README.md` | Documents Splunk index scoping, field mapping, and detection validation limits. |
| `README.md` | Contains the project title. |

## Dependencies
- Terraform 1.5 or later is required by the bootstrap configuration.
- AWS provider `~> 6.0`; the lab also uses `time ~> 0.11` and `random ~> 3.6`.
- AWS account permissions for Terraform-managed EC2, VPC, IAM, S3, SSM, and related resources.
- The userdata bucket and required Splunk and Universal Forwarder package objects must exist and be accessible.
- CI references GitHub Actions, the Terraform setup action, and Checkov.

## Configuration
- Terraform inputs and defaults are in `terraform/bootstrap/variables.tf` and `terraform/lab/variables.tf`; derived names are in `terraform/lab/locals.tf`.
- The lab region and backend settings are in `terraform/lab/main.tf` and `terraform/lab/backend.tf`.
- The public IP used for Splunk Web ingress is fetched dynamically in `terraform/lab/data.tf`.
- Keep credentials and sensitive overrides out of version control; `.gitignore` excludes Terraform state and tfvars files.
- Sigma deployment must scope Linux detections to `linux_endpoint` and Windows detections to `windows_endpoint`; normalize authentication fields before using correlations.

## Runtime Flow

```text
EC2 boot
  ├── Splunk host: bootstrap template → S3 setup scripts and Splunk package → Splunk Enterprise
  ├── Linux endpoint: bootstrap template → Linux setup → Universal Forwarder
  └── Windows endpoint: PowerShell bootstrap → Universal Forwarder → hostname update if needed

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

GitHub Actions is configured to run format, init, validate, and Checkov checks.
```

## External Services
- AWS EC2, VPC, IAM, S3, Systems Manager, and SSM Parameter Store.
- `ipv4.icanhazip.com` supplies the public client IP used for Splunk Web ingress.
- GitHub Actions, Terraform setup action, and Checkov are referenced by the CI workflow.
- Instance bootstrap accesses external sources for OS packages and Starship.

## Important Constraints
- This is a lab network: instances use one public subnet and unrestricted outbound egress.
- Terraform uploads scripts but does not create the userdata bucket or provide the Splunk and Universal Forwarder package artifacts.
- The admin password is generated by Terraform and stored in Terraform state as well as SSM; protect state access.
- AMI IDs and package versions are pinned in Terraform inputs and may need maintenance.
- The Windows bootstrap expects AWS CLI v2 to be available on its AMI.
- Sigma correlations need verified source-IP, account, and host fields; Windows failed-logon auditing must be enabled.

## Current State
- The repository contains a state-bucket bootstrap and an AWS Splunk lab Terraform configuration.
- The lab definitions include a Splunk server, Linux and Windows forwarding endpoints, SSM access, and S3-based bootstrap.
- The root README contains only the project title.

## Known Issues
- The GitHub Actions workflow uses `terraform-lab` as its working directory and Checkov target, but the Terraform configuration is under `terraform/lab`; CI paths need correction.
- `terraform/bootstrap/variables.tf` declares versioning, force-destroy, and KMS options, but `terraform/bootstrap/s3.tf` hard-codes force-destroy and AES256 encryption and does not configure versioning.
- The lab expects a pre-existing userdata bucket and package artifacts; these are not provisioned by the lab Terraform configuration.
- Sigma correlations require verified field extraction and a backend that supports Sigma correlation rules; Windows failed-logon auditing must also be enabled.

## Metadata

- Architecture version: 5
- Last updated: 2026-10-10T00:38:27+05:30
- Last full scan: 2026-10-10T00:38:27+05:30
- Files represented: 38
- Last updated by: ai
