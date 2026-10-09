locals {
  userdata_scripts = [
    "linux-setup.sh",
    "splunk-install.sh",
    "userdata-logs.sh",
    "userdata-logs.ps1",
    "linux-endpoint.sh",
    "windows-endpoint.sh",
  ]
}

# Upload userdata scripts and track file changes via MD5 hash
resource "aws_s3_object" "userdata_scripts" {
  for_each = toset(local.userdata_scripts)

  bucket = var.userdata_bucket
  key    = each.value
  source = "${path.module}/userdata/${each.value}"
  etag   = filemd5("${path.module}/userdata/${each.value}")
}

# Optional Splunk apps (e.g. Splunk Add-on for Microsoft Windows) go under the
# apps/ prefix of the bucket as .tgz/.spl; the bootstrap syncs them to the instance.
