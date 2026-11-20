# Requisitos de versión de Terraform y providers (PC-IAC-006)
# Terraform >= 1.5.0: requerido por optional() con defaults, preconditions y endswith()
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 6.0.0"    # Recursos aws_sesv2_* y atributo region (provider 6.x)
      configuration_aliases = [aws.project] # Alias Consumidor Obligatorio (PC-IAC-005)
    }
  }
}
