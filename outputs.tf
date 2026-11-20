# Outputs del módulo SES API v2 (PC-IAC-007, PC-IAC-014)

output "identity_arns" {
  description = "Map of SES email identity ARNs by identity key"
  value       = { for k, v in aws_sesv2_email_identity.this : k => v.arn }
}

output "identity_dkim_tokens" {
  description = "Map of Easy DKIM tokens by identity key (only DOMAIN identities)"
  value = {
    for k, v in aws_sesv2_email_identity.this :
    k => try(v.dkim_signing_attributes[0].tokens, [])
    if var.ses_identities_config[k].identity_type == "DOMAIN"
  }
}

output "dns_records" {
  description = "Map by identity key of the DNS records to publish in the public hosted zone: 3 DKIM CNAME, MAIL FROM MX and TXT SPF, and a suggested DMARC TXT. Empty list for EMAIL identities."
  value       = local.dns_records
}

output "configuration_set_names" {
  description = "Map of SES configuration set names by configuration set key"
  value       = { for k, v in aws_sesv2_configuration_set.this : k => v.configuration_set_name }
}

output "configuration_set_arns" {
  description = "Map of SES configuration set ARNs by configuration set key"
  value       = { for k, v in aws_sesv2_configuration_set.this : k => v.arn }
}

output "identity_policy_names" {
  description = "Map of SES sending authorization policy names by identity key"
  value       = { for k, v in aws_sesv2_email_identity_policy.this : k => v.policy_name }
}
