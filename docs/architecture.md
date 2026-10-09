# Project Architecture

## Project
- Name: `sec-splunk-linux-lab`
- Purpose: Terraform-managed AWS lab running Splunk Enterprise with Linux and Windows Universal Forwarder endpoints.
- Root: `terraform/` contains the separate state-bucket bootstrap and lab configurations.

## Directory Structure

```text
.
├── README.md
└── terraform/
    ├── bootstrap/            # Creates the Terraform state S3 bucket
    └── lab/
        ├── .github/workflows/ # Terraform CI workflow
        └── userdata/           # Instance bootstrap and setup scripts/templates
```

## Architecture

### Infrastructure
- `terraform/bootstrap/` provisions the encrypted, private S3 bucket used for Terraform state.
- `terraform/lab/` provisions the Splunk server and Linux and Windows endpoint EC2 instances.
- The lab uploads bootstrap scripts to an existing S3 bucket; software packages and optional Splunk apps are expected there as well.

### Application
- The Splunk EC2 instance installs and configures Splunk Enterprise using scripts in `terraform/lab/userdata/`.
- Linux and Windows endpoint instances install and configure Universal Forwarders to send data to the Splunk server.
- Linux setup also configures common tools and the SSM-managed user environment.

### Networking
- The lab creates a VPC with one public subnet, an internet gateway, and a default internet route.
- All three instances have public IPs and unrestricted outbound traffic.
- Splunk Web is allowed from the public IP detected during Terraform execution; receiver traffic is allowed on port 9997 from the endpoint security group.
- No inbound SSH or Splunk management port is configured; instance access is intended through Session Manager.

### Storage
- Terraform state is stored in S3: the bucket is created by `terraform/bootstrap/`, and the lab uses an S3 backend with lockfile support.
- Instance root volumes are encrypted gp3 EBS volumes.
- The lab S3 bucket stores bootstrap scripts, Universal Forwarder packages, the Splunk Enterprise package, and optionally Splunk apps.
- The Splunk admin password is stored as an SSM SecureString and is also present in Terraform state.

### IAM / Security
- Separate instance roles provide SSM access to the Splunk host and endpoint instances.
- The Splunk role can read bootstrap content and its password parameter; endpoint roles have narrower S3 access for bootstrap scripts and forwarder packages, not the password.
- EC2 metadata access requires IMDSv2. The state bucket blocks public access and uses server-side encryption.
- Security groups restrict inbound access to Splunk Web from the detected client IP and forwarding traffic from endpoints.

## Important Files

| File | Purpose |
|------|---------|
| `terraform/bootstrap/s3.tf` | Defines the Terraform state bucket, encryption, and public-access block. |
| `terraform/bootstrap/variables.tf` | Configures state-bucket naming, tags, and options. |
| `terraform/lab/main.tf` | Declares lab Terraform providers and AWS region. |
| `terraform/lab/backend.tf` | Configures the lab's S3 state backend. |
| `terraform/lab/compute.tf` | Defines Splunk and endpoint EC2 instances and their bootstrap inputs. |
| `terraform/lab/vpc.tf` | Defines the VPC, public subnet, routes, and security groups. |
| `terraform/lab/iam.tf` | Defines instance roles, policies, and profiles for SSM and S3 access. |
| `terraform/lab/s3.tf` | Uploads bootstrap scripts to the userdata bucket. |
| `terraform/lab/ssm.tf` | Generates and stores the Splunk admin password in SSM Parameter Store. |
| `terraform/lab/variables.tf` | Defines lab AMIs, networking, instance, and package settings. |
| `terraform/lab/userdata/` | Contains OS-specific bootstrap templates and Splunk/forwarder setup scripts. |
| `terraform/lab/.github/workflows/terraform.yml` | Defines the intended formatting, validation, and Checkov CI checks. |
| `README.md` | Project title; contains little operational documentation. |

## Dependencies
- Terraform 1.5 or later is required by the bootstrap configuration.
- AWS Terraform provider `~> 6.0`; lab also uses `time ~> 0.11` and `random ~> 3.6`.
- AWS account permissions for Terraform-managed EC2, VPC, IAM, S3, SSM, and related resources.
- The userdata bucket and required Splunk/Universal Forwarder package objects must be available to the lab.

## Configuration
- Terraform inputs and defaults are defined in `terraform/bootstrap/variables.tf` and `terraform/lab/variables.tf`; derived names and the SSM parameter path are in `terraform/lab/locals.tf`.
- The lab region and backend settings are in `terraform/lab/main.tf` and `terraform/lab/backend.tf`.
- Keep credentials and sensitive overrides out of version control; `.gitignore` excludes tfvars and Terraform state files.
- The public client IP used for Splunk Web ingress is fetched dynamically by `terraform/lab/data.tf`.

## Runtime Flow

```text
EC2 boot
  ├── Splunk host: bootstrap template → S3 setup scripts → Splunk Enterprise install
  ├── Linux endpoint: bootstrap template → shared Linux setup → Linux forwarder setup
  └── Windows endpoint: PowerShell bootstrap → Windows forwarder setup

Linux and Windows Universal Forwarders ── TCP 9997 ──> Splunk Enterprise
Operator ── HTTPS 8000 ──> Splunk Web
Operator ── AWS Systems Manager Session Manager ──> EC2 instances
```

## Deployment Flow

```text
terraform/bootstrap/
  └── terraform init / apply → state S3 bucket

terraform/lab/
  └── configure backend → terraform init → plan / apply
        ├── create VPC, IAM, SSM parameter, and S3 script objects
        └── create EC2 instances and run their bootstrap flows

GitHub Actions is intended to run format, init, validate, and Checkov checks.
```

## External Services
- AWS EC2, VPC, IAM, S3, Systems Manager, and SSM Parameter Store.
- `ipv4.icanhazip.com` provides the public client IP used for Splunk Web ingress.
- GitHub Actions, Terraform setup action, and Checkov are referenced by the CI workflow.
- Instance bootstrap downloads OS packages and Starship from external sources.

## Important Constraints
- The lab is a single-public-subnet setup with public IPs and unrestricted outbound egress; it is intended as a lab, not a production network design.
- The userdata bucket, Splunk Enterprise package, and Universal Forwarder packages are prerequisites; Terraform uploads scripts but does not provision these package artifacts.
- The admin password is generated by Terraform and stored in Terraform state as well as SSM; state access must be protected.
- AMI IDs and package versions are configured in Terraform variables and may need maintenance.

## Current State
- The repository contains two Terraform configurations: a state-bucket bootstrap and an AWS Splunk lab.
- Infrastructure definitions include a Splunk server, Linux and Windows forwarding endpoints, SSM access, and S3-based bootstrap.
- The root README provides only the project title.

## Known Issues
- The GitHub Actions workflow uses `terraform-lab` as its working directory and Checkov target, but the configuration directory in the repository is `terraform/lab`; the workflow paths need correction for CI to run against the lab.
- The lab expects pre-existing S3 package artifacts and userdata bucket; these are not created by the Terraform configuration shown.

## Metadata

- Architecture version: 1
- Last updated: 2026-10-09T20:28:40+05:30
- Last full scan: 2026-10-09T20:28:40+05:30
- Files represented: 30
- Last updated by: ai
