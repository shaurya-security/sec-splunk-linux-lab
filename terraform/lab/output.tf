output "output_time_ist-----------" {
  description = "Execution timestamp in IST (UTC+5:30)"
  value       = formatdate("YYYY-MM-DD hh:mm:ss", timeadd(timestamp(), "5h30m")) # IST
}

output "splunk_private_ip---------" {
  value = aws_instance.splunk.private_ip
}

output "splunk_public_ip----------" {
  value = aws_instance.splunk.public_ip
}

output "splunk_id-----------------" {
  value = aws_instance.splunk.id
}

output "splunk_web_url------------" {
  description = "Splunk Web (HTTPS, self-signed cert). Ready a few minutes after apply."
  value       = "https://${aws_instance.splunk.public_ip}:8000"
}

output "splunk_sg_id--------------" {
  value = aws_security_group.splunk_sg.id
}

output "my_current_public_ip------" {
  value       = chomp(data.http.my_public_ip.response_body)
  description = "The local public IP address fetched dynamically during terraform run."
}
