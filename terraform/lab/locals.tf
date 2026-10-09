locals {

  owner    = var.owner
  vpc_name = "${local.owner}-vpc"
  igw_name = "${local.owner}-igw"

  subnet_name        = "${local.owner}-subnet"
  public_subnet_name = "${local.subnet_name}-public"

  rtb_name        = "${local.owner}-rtb"
  public_rtb_name = "${local.rtb_name}-public"

  sg_name         = "${local.owner}-sg"
  splunk_sg_name  = "${local.sg_name}-splunk"
  ec2_name        = "${local.owner}-instance"
  splunk_ec2_name = "${local.ec2_name}-splunk"

  linux_endpoint_hostname   = "linux-endpoint-01"
  windows_endpoint_hostname = "windows-endpoint-01"

  splunk_password_param = "/${local.owner}/splunk/admin-password"
}
