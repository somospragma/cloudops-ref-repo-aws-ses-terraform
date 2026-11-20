# Valores de variables para el ejemplo (PC-IAC-026)
# Configuración declarativa sin IDs hardcodeados:
# - account_id → data.aws_caller_identity (data.tf)
# - sns_topic_arn → data.aws_sns_topic (data.tf), con use_sns_topic = true
# - principals → se construye en locals.tf desde delegated_senders
# - deploy_role_arn → se inyecta desde el pipeline (TF_VAR_deploy_role_arn)
#
# Caso de uso: la cuenta pragma-main (654767188854) envía como pragma.com.co y autoriza
# a la lambda license-processing de la cuenta 533267042257 a enviar SOLO como
# licenciasgenial@pragma.com.co.

client      = "pragma"
project     = "notif"
environment = "pdn"
region      = "us-east-1"

common_tags = {
  Client      = "pragma"
  Project     = "notif"
  Environment = "pdn"
  Owner       = "cloudops-team"
  CostCenter  = "pragma-main"
}

# Remitente delegado cross-account (cuenta externa: no se puede consultar con data sources)
delegated_senders = {
  "license-processing" = {
    account_id = "533267042257"
    role_name  = "license-processing-lambda-role" # Reemplazar por el nombre real del rol de la lambda
  }
}

# Topic SNS existente: pragma-notif-pdn-sns-ses-events (módulo SNS de somospragma)
ses_events_sns_topic_key = "ses-events"

ses_identities_config = {
  "pragma" = {
    identity                = "pragma.com.co"
    identity_type           = "DOMAIN"
    dkim_signing_key_length = "RSA_2048_BIT"
    configuration_set_key   = "default"

    mail_from = {
      domain                 = "mail.pragma.com.co"
      behavior_on_mx_failure = "USE_DEFAULT_VALUE"
    }

    sending_authorization = {
      "AllowLicenseProcessingLambda" = {
        delegated_sender_key   = "license-processing" # principals se inyecta en locals.tf
        allowed_from_addresses = ["licenciasgenial@pragma.com.co"]
      }
    }

    functionality = "transactional-email"
    additional_tags = {
      Domain = "workload"
    }
  }
}

ses_configuration_sets_config = {
  "default" = {
    tls_policy                 = "REQUIRE"
    reputation_metrics_enabled = true
    sending_enabled            = true
    suppressed_reasons         = ["BOUNCE", "COMPLAINT"]

    event_destinations = {
      "events" = {
        matching_event_types = ["BOUNCE", "COMPLAINT"]
        use_sns_topic        = true # sns_topic_arn se inyecta desde data.tf
      }
    }

    functionality = "transactional-email"
    additional_tags = {
      Domain = "workload"
    }
  }
}
