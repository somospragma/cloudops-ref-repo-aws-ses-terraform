# Data sources del ejemplo (PC-IAC-011, PC-IAC-017, PC-IAC-026)

# Partición actual (aws, aws-us-gov, aws-cn) para construir ARN de roles delegados
data "aws_partition" "current" {
  provider = aws.principal
}

# Cuenta actual: dueña de las identidades SES (se inyecta como account_id)
data "aws_caller_identity" "current" {
  provider = aws.principal
}

# Topic SNS existente que recibe los eventos BOUNCE / COMPLAINT de SES
# Búsqueda por nombre estándar PC-IAC-003: {client}-{project}-{environment}-sns-{key}
data "aws_sns_topic" "ses_events" {
  provider = aws.principal
  name     = "${local.governance_prefix}-sns-${var.ses_events_sns_topic_key}"
}
