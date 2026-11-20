# sample/outputs.tf
# Outputs del ejemplo para validar la infraestructura creada

output "identity_arns" {
  description = "ARNs of the SES email identities"
  value       = module.ses.identity_arns
}

output "identity_dkim_tokens" {
  description = "Easy DKIM tokens of the DOMAIN identities"
  value       = module.ses.identity_dkim_tokens
}

output "dns_records" {
  description = "DNS records to publish in the public hosted zone (DKIM, MAIL FROM and suggested DMARC)"
  value       = module.ses.dns_records
}

output "configuration_set_names" {
  description = "Names of the SES configuration sets"
  value       = module.ses.configuration_set_names
}

output "configuration_set_arns" {
  description = "ARNs of the SES configuration sets"
  value       = module.ses.configuration_set_arns
}

output "identity_policy_names" {
  description = "Names of the sending authorization policies"
  value       = module.ses.identity_policy_names
}
