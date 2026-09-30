# AMI is pinned via var.linux_ami_id (no dynamic lookup).

data "http" "my_public_ip" {
  url = "https://ipv4.icanhazip.com"
}
