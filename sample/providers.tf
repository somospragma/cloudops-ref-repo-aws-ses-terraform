# Configuración de providers para el ejemplo (PC-IAC-005, PC-IAC-006, PC-IAC-008)

provider "aws" {
  region = var.region
  alias  = "principal"

  # Asunción de rol de despliegue con menor privilegio (PC-IAC-005)
  assume_role {
    role_arn = var.deploy_role_arn
  }

  default_tags {
    tags = var.common_tags # PC-IAC-004
  }
}

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73.0" # Pinning estricto en Root (PC-IAC-006)
    }
  }

  # Backend S3 parcial: bucket, key y region se inyectan en terraform init (PC-IAC-008)
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}
