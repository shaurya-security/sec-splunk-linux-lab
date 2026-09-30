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

