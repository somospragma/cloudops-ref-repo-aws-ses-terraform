############################################################################
# Invocación del Módulo Padre (SES) - PC-IAC-013, PC-IAC-026
############################################################################
module "ses" {
  # A. Fuente del módulo (PC-IAC-015: ruta local solo para desarrollo del sample)
  source = "../"

  # B. Providers (PC-IAC-005)
  providers = {
    aws.project = aws.principal
  }

  # C. Variables de Gobernanza (PC-IAC-003)
  client      = var.client
  project     = var.project
  environment = var.environment

  # D. Variables Transversales (PC-IAC-011)
  account_id = data.aws_caller_identity.current.account_id

  # E. Configuración transformada desde locals (PC-IAC-026)
  ses_identities_config         = local.ses_identities_config_transformed
  ses_configuration_sets_config = local.ses_configuration_sets_config_transformed
}
