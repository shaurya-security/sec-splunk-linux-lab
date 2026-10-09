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

resource "aws_instance" "linux_endpoint" {
  ami                         = var.linux_endpoint_ami_id
  instance_type               = "m7i-flex.large"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.endpoint_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.endpoint_ssm.name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/userdata/linux-endpoint-bootstrap.sh.tpl", {
    s3_bucket         = var.userdata_bucket
    splunk_private_ip = aws_instance.splunk.private_ip
    uf_s3_prefix      = var.uf_s3_prefix
    uf_package_key    = var.linux_uf_package_key
  })
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${local.owner}-linux-endpoint"
    Role = "Splunk Linux endpoint"
  }

  depends_on = [
    aws_route_table_association.public_association,
    aws_instance.splunk,
    aws_s3_object.userdata_scripts,
    aws_iam_role_policy.endpoint_bootstrap_and_uf_s3_read,
    aws_iam_role_policy_attachment.endpoint_ssm,
  ]
}

resource "aws_instance" "windows_endpoint" {
  ami                         = var.windows_endpoint_ami_id
  instance_type               = "m7i-flex.large"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.endpoint_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.endpoint_ssm.name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/userdata/windows-endpoint-bootstrap.ps1.tpl", {
    s3_bucket         = var.userdata_bucket
    splunk_private_ip = aws_instance.splunk.private_ip
    uf_s3_prefix      = var.uf_s3_prefix
    uf_package_key    = var.windows_uf_package_key
    aws_region        = "ap-south-1"
  })
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${local.owner}-windows-endpoint"
    Role = "Splunk Windows endpoint"
  }

  depends_on = [
    aws_route_table_association.public_association,
    aws_instance.splunk,
    aws_s3_object.userdata_scripts,
    aws_iam_role_policy.endpoint_bootstrap_and_uf_s3_read,
    aws_iam_role_policy_attachment.endpoint_ssm,
  ]
}
