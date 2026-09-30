locals {

  owner    = var.owner
  vpc_name = "${local.owner}-vpc"
  igw_name = "${local.owner}-igw"

  subnet_name        = "${local.owner}-subnet"
  public_subnet_name = "${local.subnet_name}-public"
  #  private_subnet_name = "${local.subnet_name}-private"

  rtb_name        = "${local.owner}-rtb"
  public_rtb_name = "${local.rtb_name}-public"
  #  private_rtb_name = "${local.rtb_name}-private"

  sg_name         = "${local.owner}-sg"
  splunk_sg_name  = "${local.sg_name}-splunk"
  ec2_name        = "${local.owner}-instance"
  splunk_ec2_name = "${local.ec2_name}-splunk"

  splunk_password_param = "/${local.owner}/splunk/admin-password"
}
