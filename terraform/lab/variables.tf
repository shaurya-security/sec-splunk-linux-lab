variable "linux_ami_id" {
  description = "Pinned Amazon Linux 2023 AMI ID (x86_64)"
  type        = string
  default     = "ami-094210f044117049d"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "owner" {
  type    = string
  default = "shaurya"
}

variable "userdata_bucket" {
  type    = string
  default = "shaurya-terraform-userdata-2026"
}

variable "splunk_instance_type" {
  description = "x86_64 instance type for Splunk (2 vCPU / 8 GB is comfortable for a lab)"
  type        = string
  default     = "m7i-flex.large"
}

variable "splunk_root_volume_gb" {
  description = "Root volume size. Splunk stops indexing when free disk gets low, so keep >= 30."
  type        = number
  default     = 30
}

variable "timezone" {
  description = "Timezone for the OS and the Splunk admin user"
  type        = string
  default     = "Asia/Kolkata"
}


variable "linux_endpoint_ami_id" {
  description = "x86_64 Linux AMI ID for the Linux endpoint. Defaults to the pinned Amazon Linux 2023 AMI."
  type        = string
  default     = "ami-094210f044117049d"
}

variable "windows_endpoint_ami_id" {
  description = "Latest Windows Server 2025 English Full Base x86_64 AMI ID in ap-south-1."
  type        = string
  default     = "ami-048d6ed8eabb546f1"
}

variable "uf_s3_prefix" {
  description = "S3 prefix holding the Universal Forwarder packages."
  type        = string
  default     = "splunk/10.4.3"
}

variable "linux_uf_package_key" {
  description = "S3 object name of the x86_64 Linux Universal Forwarder RPM in uf_s3_prefix."
  type        = string
  default     = "splunkforwarder-10.4.3-4174a2deda5d.x86_64.rpm"
}

variable "windows_uf_package_key" {
  description = "S3 object name of the x64 Windows Universal Forwarder MSI in uf_s3_prefix."
  type        = string
  default     = "splunkforwarder-10.4.3-4174a2deda5d-windows-x64.msi"
}
