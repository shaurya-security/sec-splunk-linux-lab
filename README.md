# Security Splunk Linux Lab

Terraform provisions a small AWS lab with Splunk Enterprise, an Amazon Linux endpoint, and a Windows endpoint. Universal Forwarders send Linux auditd and Windows Security events to Splunk. Experimental Sigma rules describe authentication-failure and correlation detections.

> **Lab warning:** This design places instances in a public subnet and allows unrestricted outbound traffic. Splunk Web is limited to the operator IP, and endpoint access is intended through AWS Systems Manager Session Manager. It is not a production network design.

## What is deployed

- Splunk Enterprise on an Amazon Linux 2023 EC2 instance.
- A Linux endpoint that forwards `/var/log/audit/audit.log` to `linux_endpoint` (`linux_audit` sourcetype).
- A Windows endpoint that forwards Application, System, and Security event channels to `windows_endpoint`.
- A VPC with one public subnet in `ap-south-1a`, an internet gateway, and security groups allowing Splunk Web on TCP 8000 from the detected operator IP and Universal Forwarder traffic on TCP 9997 from the endpoint security group.
- Session Manager access; no inbound SSH, RDP, or Splunk management port 8089.
- An SSM SecureString containing the generated Splunk admin password.

## Requirements

- Terraform 1.10 or later for the lab S3 backend lockfile (the bootstrap configuration itself requires Terraform 1.5+), and AWS credentials configured outside this repository.
- AWS permissions for EC2, VPC, IAM, S3, SSM Parameter Store, and Systems Manager.
- The required install packages in the pre-existing userdata S3 bucket before creating instances:

| Object key | Package |
|---|---|
| `splunk/10.4.3/splunk-10.4.3-4174a2deda5d.x86_64.rpm` | Splunk Enterprise for Linux |
| `splunk/10.4.3/splunkforwarder-10.4.3-4174a2deda5d.x86_64.rpm` | Linux Universal Forwarder |
| `splunk/10.4.3/splunkforwarder-10.4.3-4174a2deda5d-windows-x64.msi` | Windows Universal Forwarder |

The default userdata bucket is `shaurya-terraform-userdata-2026`; the package prefix and filenames can be changed in `terraform/lab/variables.tf`. Terraform uploads the bootstrap scripts, but does not create this bucket or upload the software packages. Windows bootstrap installs AWS CLI v2 from AWS’s official signed MSI if the AMI does not include it.

## Deploy

The bootstrap configuration creates the S3 bucket used for the lab's remote state. Its default name matches the bucket configured in `terraform/lab/backend.tf`.

```bash
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap plan
terraform -chdir=terraform/bootstrap apply

terraform -chdir=terraform/lab init
terraform -chdir=terraform/lab plan
terraform -chdir=terraform/lab apply
```

Review the plan before applying. `terraform/lab/compute.tf` enables `user_data_replace_on_change` for all three instances and hashes staged scripts into user data. A script change can therefore replace the instance that consumes it. Root EBS volumes use `delete_on_termination = true`, so local instance data is lost on replacement.

The bootstrap bucket currently has `force_destroy = true`; destroying that configuration can remove its objects, including lab state. Protect the backend bucket and state.

## Access and operations

- Use **AWS Systems Manager Session Manager** to connect to instances.
- Run `terraform -chdir=terraform/lab output` for instance IDs and the Splunk Web URL. Splunk Web uses HTTPS with a self-signed certificate on port 8000; ingress is restricted to the public IP detected during Terraform execution.
- The Windows bootstrap stages setup scripts, logs, MSI packages, and authored forwarder configs under `C:\Soc-Lab`. Authored `inputs.conf` and `outputs.conf` are copied into the Universal Forwarder's app directory. A PowerShell profile is configured to start in `C:\Soc-Lab`.
- Linux bootstrap diagnostics are available as `/home/ssm-user/userdata-logs.sh`; select `splunk` or `linux-endpoint` if automatic host detection is unavailable. Windows diagnostics are at `C:\Soc-Lab\userdata-logs.ps1`.
- Diagnostic helpers show progress markers and completion/error status from bootstrap logs. They do not prove that the forwarder is connected to Splunk; check the forwarder service and receiver connections separately.

## Search in Splunk

Use **Search & Reporting** and choose an appropriate time range:

```spl
index=linux_endpoint sourcetype=linux_audit
```

```spl
index=windows_endpoint
```

Windows Security events are collected with XML rendering. In current events, the event ID remains in raw XML rather than being extracted as `EventCode`; this is a Splunk field-extraction issue, not a Sigma rule issue. Sigma rules in this repository are not automatically converted or run.

Search the raw XML for failed logons (Event ID 4625):

```spl
index=windows_endpoint "<EventID>4625</EventID>"
```

To extract the XML event ID for one search and summarize it:

```spl
index=windows_endpoint "<EventID>4625</EventID>"
| rex field=_raw "<EventID>(?<EventID>[0-9]+)</EventID>"
| stats count by EventID host
```

## Sigma detections

Experimental Linux and Windows event rules and correlation rules are in `detections/sigma/`. See [`detections/sigma/README.md`](detections/sigma/README.md) for index scoping, field normalization, correlation requirements, and validation guidance. The Sigma rules are source files; a Sigma-to-Splunk conversion/deployment workflow is not configured yet.

The endpoint security groups have no inbound rules, so public SSH/RDP brute-force attempts cannot reach these endpoints. Do not open public SSH/RDP for testing; use controlled local or synthetic events.

## Validation and CI

From the repository root:

```bash
terraform -chdir=terraform/lab fmt -check -recursive
terraform -chdir=terraform/lab validate
```

The Terraform workflow is currently located under `terraform/lab/.github/workflows/`; GitHub Actions normally discovers workflows only from the repository-root `.github/workflows/`. Its working-directory and Checkov target also need to match `terraform/lab` before CI can be relied upon.

## Configuration

- Lab variables and defaults are in `terraform/lab/variables.tf`; use a local `terraform/lab/terraform.tfvars` for overrides. Terraform state and tfvars files are ignored by Git.
- The lab uses region `ap-south-1`. The S3 backend bucket and key are configured in `terraform/lab/backend.tf`.
- Default instance names are `splunk-server`, `linux-endpoint-01`, and `windows-endpoint-01`.
- The Splunk admin password parameter defaults to `/shaurya/splunk/admin-password` (derived from `owner`). Retrieve it securely from SSM Parameter Store; it is also present in Terraform state.

## User-data diagnostics

Bootstrap scripts emit progress, completion, and error markers. Helpers summarize these markers and colorize their output when run interactively:

- Linux: `/home/ssm-user/userdata-logs.sh` (optionally pass `splunk` or `linux-endpoint`).
- Windows: `C:\Soc-Lab\userdata-logs.ps1`.

A completed bootstrap does not by itself prove a forwarder is connected. Check the forwarder service and TCP 9997 receiver connection separately. Windows bootstrap artifacts, logs, and authored configs are staged under `C:\Soc-Lab`; the Universal Forwarder also needs its installed app configs under its own install directory.

## Security and lifecycle notes

- Do not commit AWS credentials, secrets, or populated tfvars files. The generated Splunk password is stored in Terraform state, so restrict access to the state bucket.
- The Windows endpoint is bootstrapped through a signed AWS CLI v2 MSI downloaded from AWS when the AMI lacks the CLI.
- All EC2 instances use `user_data_replace_on_change = true`. Changes to hashed user-data scripts can replace affected instances. Review `terraform plan` before applying; root volumes are deleted on termination, so local instance data will be lost.
- The bootstrap bucket currently hard-codes `force_destroy = true`. Destroying the bootstrap configuration can delete the remote lab state object; do not destroy it casually.
- The GitHub Actions workflow is stored under `terraform/lab/.github/workflows/`, where GitHub will not discover it automatically. Its configured working directory and Checkov path also need updating to `terraform/lab`.

## Project layout

```text
.
├── detections/sigma/       # Experimental Linux, Windows, and correlation rules
├── docs/                   # Architecture and changelog
└── terraform/
    ├── bootstrap/          # State bucket configuration
    └── lab/                # Splunk lab infrastructure and userdata
```

### Upload the prerequisite packages

After obtaining the Splunk Enterprise and Universal Forwarder packages under the expected filenames, upload them to the userdata bucket before applying the lab configuration:

```bash
aws s3 cp ./splunk-10.4.3-4174a2deda5d.x86_64.rpm s3://shaurya-terraform-userdata-2026/splunk/10.4.3/splunk-10.4.3-4174a2deda5d.x86_64.rpm
aws s3 cp ./splunkforwarder-10.4.3-4174a2deda5d.x86_64.rpm s3://shaurya-terraform-userdata-2026/splunk/10.4.3/splunkforwarder-10.4.3-4174a2deda5d.x86_64.rpm
aws s3 cp ./splunkforwarder-10.4.3-4174a2deda5d-windows-x64.msi s3://shaurya-terraform-userdata-2026/splunk/10.4.3/splunkforwarder-10.4.3-4174a2deda5d-windows-x64.msi
```

Adjust the destination bucket if `userdata_bucket` is overridden. Package downloads/licensing are the operator's responsibility.

The Splunk admin password parameter defaults to `/shaurya/splunk/admin-password` (`owner` controls the prefix). Retrieve it securely through Systems Manager Parameter Store; do not paste it into terminal transcripts or commit it.
