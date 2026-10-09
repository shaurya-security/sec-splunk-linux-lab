resource "aws_iam_role" "ec2_ssm_role" {
  name = "terraform-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "ec2.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "terraform-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm_role.name
}

# Bootstrap files from S3 (GetObject for files, ListBucket for the apps/ sync)
resource "aws_iam_role_policy" "userdata_s3_read" {
  name = "userdata-s3-read"
  role = aws_iam_role.ec2_ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::${var.userdata_bucket}/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::${var.userdata_bucket}"
      }
    ]
  })
}

# Read ONLY the Splunk admin password parameter.
# (Default aws/ssm key needs no extra KMS permission. If you switch the
# parameter to a customer-managed key, add kms:Decrypt on that key.)
resource "aws_iam_role_policy" "splunk_password_read" {
  name = "splunk-password-read"
  role = aws_iam_role.ec2_ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ssm:GetParameter"
      Resource = aws_ssm_parameter.splunk_admin_password.arn
    }]
  })
}

resource "time_sleep" "wait_for_iam" {
  create_duration = "30s"

  depends_on = [
    aws_iam_instance_profile.ec2_ssm,
    aws_iam_role_policy.userdata_s3_read,
    aws_iam_role_policy.splunk_password_read,
    aws_iam_role_policy_attachment.ec2_ssm
  ]
}

# Endpoint instances receive SSM access and read-only access only to the UF package prefix.
# They do not receive access to the Splunk admin-password parameter.
resource "aws_iam_role" "endpoint_ssm_role" {
  name = "terraform-endpoint-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "endpoint_bootstrap_and_uf_s3_read" {
  name = "endpoint-bootstrap-and-uf-read"
  role = aws_iam_role.endpoint_ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "s3:GetObject"
      Resource = [
        "arn:aws:s3:::${var.userdata_bucket}/${var.uf_s3_prefix}/*",
        "arn:aws:s3:::${var.userdata_bucket}/linux-setup.sh",
        "arn:aws:s3:::${var.userdata_bucket}/linux-endpoint.sh",
        "arn:aws:s3:::${var.userdata_bucket}/windows-endpoint.sh",
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "endpoint_ssm" {
  role       = aws_iam_role.endpoint_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "endpoint_ssm" {
  name = "terraform-endpoint-ssm-profile"
  role = aws_iam_role.endpoint_ssm_role.name
}
