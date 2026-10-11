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
│       ├── correlation/        # Brute-force and password-spray rules
│       └── pipelines/          # Splunk index and field mappings
├── terraform/
│   ├── bootstrap/              # S3 bucket for remote Terraform state
│   └── lab/
│       ├── .github/workflows/  # Terraform CI
│       └── userdata/           # EC2 bootstrap templates and scripts
└── splunk-updated.zip          # Packaged artifact
```

## Architecture

### Infrastructure
- `terraform/bootstrap/` creates the S3 bucket used for the lab's Terraform state.
- `terraform/lab/` provisions the AWS network, IAM and SSM resources, bootstrap-script objects, and Splunk, Linux endpoint, and Windows endpoint EC2 instances.
- The lab expects a pre-existing userdata S3 bucket containing Splunk and Universal Forwarder packages and optional Splunk apps.

### Application
- `terraform/lab/userdata/` bootstraps Splunk Enterprise and the Linux and Windows Universal Forwarders.
- Linux auditd logs are collected on the Splunk host and Linux endpoint into separate indexes; Windows Security events are forwarded to the Windows endpoint index.
- The Splunk host installs optional `Splunk_TA_windows` and `Splunk_TA_nix` add-ons from the userdata bucket. They provide search-time field extraction; missing packages produce warnings rather than stopping bootstrap.
- `detections/sigma/` holds experimental event and correlation rules. `pipelines/lab_splunk.yml` adds Splunk index/source scope and maps fields to the names expected by the rules.
- User-data templates hash setup scripts; changes can replace their consuming instances. Windows bootstrap artifacts, logs, and authored configs are staged under `C:\Soc-Lab`.

### Networking
- The lab creates a VPC, one public subnet in `ap-south-1a`, an internet gateway, and a default internet route.
- All three instances receive public IPs and unrestricted outbound traffic.
- Splunk Web on port 8000 is restricted to the operator IP detected during Terraform execution. TCP 9997 receiver ingress is allowed from the endpoint security group.
- Endpoint security groups have no inbound rules. SSH and Splunk management port 8089 are not exposed; Session Manager is the intended access path.

### Storage
- Bootstrap Terraform uses local state; lab Terraform uses an encrypted S3 backend with lockfile support.
- The state bucket enables AES256 encryption and blocks public access. Its `force_destroy` value is hard-coded; declared versioning and KMS options are not applied.
- EC2 root volumes are encrypted gp3 EBS volumes and are deleted when instances terminate.
- The userdata bucket holds uploaded setup scripts, packages, and optional Splunk apps.
- The Splunk admin password is stored in SSM Parameter Store as a SecureString and is also present in Terraform state.

### IAM / Security
- Separate instance roles provide Session Manager access to the Splunk host and endpoints.
- The Splunk role can read userdata objects and its password parameter. Endpoint roles can read bootstrap assets and Universal Forwarder packages, but not the password parameter.
- EC2 metadata access requires IMDSv2.
- Security groups restrict inbound access to Splunk Web from the operator IP and forwarding traffic from the endpoint security group.

## Important Files

| File | Purpose |
|------|---------|
| `README.md` | Overview, prerequisites, deployment, access, and lab safety notes. |
| `terraform/bootstrap/backend.tf` | Configures local state for the state-bucket bootstrap. |
| `terraform/bootstrap/s3.tf` | Defines the Terraform state bucket, encryption, and public-access block. |
| `terraform/bootstrap/variables.tf` | Declares bootstrap inputs, including options not currently applied by `s3.tf`. |
| `terraform/lab/main.tf` | Declares lab providers and AWS region. |
| `terraform/lab/backend.tf` | Configures the lab S3 state backend. |
| `terraform/lab/compute.tf` | Defines EC2 instances and their bootstrap inputs. |
| `terraform/lab/vpc.tf` | Defines the VPC, subnet, routes, and security groups. |
| `terraform/lab/iam.tf` | Defines instance roles, policies, and profiles. |
| `terraform/lab/s3.tf` | Uploads bootstrap scripts to the userdata bucket. |
| `terraform/lab/ssm.tf` | Generates and stores the Splunk admin password in SSM Parameter Store. |
| `terraform/lab/userdata/` | Contains instance bootstrap templates, setup scripts, and diagnostic helpers. |
| `terraform/lab/.github/workflows/terraform.yml` | Runs Terraform format, init, validate, and Checkov CI steps. |
| `terraform/lab/userdata/splunk-install.sh` | Installs Splunk Enterprise, configures lab telemetry, and installs available add-ons. |
| `detections/sigma/` | Contains Linux and Windows authentication rules and correlation rules. |
| `detections/sigma/pipelines/lab_splunk.yml` | Maps lab indexes, sources, and fields for Sigma conversion. |
| `detections/sigma/README.md` | Documents rule conventions, add-ons, field mappings, and validation guidance. |

## Dependencies
- Terraform 1.5 or later for bootstrap; Terraform 1.10 or later for the lab S3 backend lockfile.
- AWS provider `~> 6.0`; lab also uses `time ~> 0.11` and `random ~> 3.6`.
- AWS account permissions for the EC2, VPC, IAM, S3, Systems Manager, and SSM Parameter Store resources.
- A pre-existing userdata bucket and required Splunk and Universal Forwarder package objects.
- Optional Splunk Windows and Unix/Linux add-on packages in the userdata bucket's `apps/` prefix.
- CI references GitHub Actions, the Terraform setup action, and Checkov.

## Configuration
- Terraform inputs and defaults are in `terraform/bootstrap/variables.tf` and `terraform/lab/variables.tf`; derived names are in `terraform/lab/locals.tf`.
- AWS region and backend settings are in `terraform/lab/main.tf` and `terraform/lab/backend.tf`.
- `terraform/lab/data.tf` fetches the operator's public IP for Splunk Web ingress.
- Keep credentials and sensitive overrides out of version control; `.gitignore` excludes Terraform state and tfvars files.
- Sigma conversion uses `detections/sigma/pipelines/lab_splunk.yml`; the Sigma README documents post-deploy field checks.

## Runtime Flow

```text
EC2 boot
  ├── Splunk host: bootstrap template → S3 setup scripts/packages → Splunk Enterprise
  ├── Linux endpoint: bootstrap template → Linux setup → Universal Forwarder
  └── Windows endpoint: PowerShell bootstrap → Universal Forwarder

Linux and Windows Universal Forwarders ── TCP 9997 ──> Splunk Enterprise
Operator ── HTTPS 8000 ──> Splunk Web
Operator ── AWS Systems Manager Session Manager ──> EC2 instances
Forwarded authentication events ──> Splunk indexes ──> Sigma rules/pipeline
```

## Deployment Flow

```text
terraform/bootstrap/
  └── terraform init / plan / apply → state S3 bucket

terraform/lab/
  └── configure backend → terraform init / plan / apply
        ├── create network, IAM, SSM parameter, and S3 script objects
        └── create EC2 instances and run bootstrap flows

GitHub Actions runs Terraform and Checkov checks.
```

## External Services
- AWS EC2, VPC, IAM, S3, Systems Manager, and SSM Parameter Store.
- `ipv4.icanhazip.com` supplies the public client IP used for Splunk Web ingress.
- GitHub Actions, the Terraform setup action, and Checkov are referenced by CI.
- Bootstrap retrieves packages and setup dependencies from S3 and external package sources; Windows bootstrap can download AWS CLI v2 from AWS if it is absent.

## Important Constraints
- This is a lab network: instances use one public subnet and unrestricted outbound egress.
- Terraform uploads scripts but does not create the userdata bucket or provide Splunk and Universal Forwarder package artifacts.
- Protect Terraform state; it contains the generated Splunk admin password.
- AMI IDs and package versions are pinned and may need maintenance.
- Changes to hashed user-data scripts can replace EC2 instances; their root volumes are deleted on termination.
- Sigma correlations depend on verified field extraction, source-IP/account/host fields, backend support for correlation rules, and enabled Windows failed-logon auditing.

## Current State
- The repository contains a state-bucket bootstrap and an AWS Splunk lab Terraform configuration.
- The lab defines a Splunk server, Linux and Windows forwarding endpoints, Session Manager access, and S3-based bootstrap.
- The root README documents prerequisites, deployment, access, operations, and lifecycle warnings.

## Known Issues
- `terraform/lab/.github/workflows/terraform.yml` sets its working directory and Checkov target to `terraform-lab`, but the configuration is under `terraform/lab`; CI paths need correction.
- `terraform/bootstrap/variables.tf` declares versioning, force-destroy, and KMS options, but `terraform/bootstrap/s3.tf` hard-codes force-destroy and AES256 encryption and does not configure versioning.
- The lab expects a pre-existing userdata bucket and package artifacts; these are not provisioned by the lab Terraform configuration.
- Sigma rules and correlations need validation against live Splunk data and generated SPL before alerting. Missing add-ons do not fail Splunk bootstrap; check the Splunk install log for warnings.

## Metadata

- Architecture version: 17
- Last updated: 2026-10-11T09:58:33+05:30
- Last full scan: 2026-10-11T09:58:33+05:30
- Files represented: 40
- Last updated by: ai
