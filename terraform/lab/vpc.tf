########################################
# VPC
########################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = local.vpc_name
  }
}

########################################
# Public Subnet
########################################

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = local.public_subnet_name
  }
}

########################################
# Internet Gateway
########################################

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = local.igw_name
  }
}

########################################
# Public Route Table
########################################

resource "aws_route_table" "public_rtb" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = local.public_rtb_name
  }
}

resource "aws_route_table_association" "public_association" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rtb.id
}

########################################
# Splunk Security Group
########################################

resource "aws_security_group" "splunk_sg" {
  name        = local.splunk_sg_name
  description = "Splunk Enterprise"
  vpc_id      = aws_vpc.main.id

  # Splunk Web (HTTPS) - your IP only
  ingress {
    description = "Splunk Web"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.my_public_ip.response_body)}/32"]
  }

  # Universal Forwarders can connect only from the endpoint security group.
  ingress {
    description     = "Splunk Universal Forwarder receiver"
    from_port       = 9997
    to_port         = 9997
    protocol        = "tcp"
    security_groups = [aws_security_group.endpoint_sg.id]
  }

  # 8089 (management) intentionally NOT exposed. Access the box via Session Manager.

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_security_group" "endpoint_sg" {
  name        = "${local.owner}-endpoint-sg"
  description = "Linux and Windows Splunk endpoint instances"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow outbound package downloads, SSM, and Splunk forwarding"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
