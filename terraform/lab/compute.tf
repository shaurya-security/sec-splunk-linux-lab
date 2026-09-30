resource "aws_instance" "splunk" {
  ami                         = var.linux_ami_id
  instance_type               = var.splunk_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.splunk_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/userdata/bootstrap.sh.tpl", {
    s3_bucket      = var.userdata_bucket
    timezone       = var.timezone
    password_param = local.splunk_password_param
    script_hash    = filemd5("${path.module}/userdata/splunk-install.sh")
    common_hash    = filemd5("${path.module}/userdata/linux-setup.sh")
  })
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = var.splunk_root_volume_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = local.splunk_ec2_name
  }

  depends_on = [
    time_sleep.wait_for_iam,
    aws_s3_object.userdata_scripts,
    aws_ssm_parameter.splunk_admin_password,
    aws_route_table_association.public_association,
  ]
}
