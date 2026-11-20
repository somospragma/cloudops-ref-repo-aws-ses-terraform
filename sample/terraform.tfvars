# Valores de variables para el ejemplo (PC-IAC-026)
# Datos dummy: reemplazar por los valores de cada proyecto.
# Configuración declarativa sin IDs hardcodeados:
# - account_id → data.aws_caller_identity (data.tf)
# - sns_topic_arn → data.aws_sns_topic (data.tf), con use_sns_topic = true
# - principals → se construye en locals.tf desde delegated_senders
# - deploy_role_arn → se inyecta desde el pipeline (TF_VAR_deploy_role_arn)
#
# Caso de ejemplo: la cuenta dueña verifica example.com y autoriza a una lambda de la
# cuenta 222222222222 a enviar SOLO como no-reply@example.com.

client      = "acme"
project     = "notif"
environment = "dev"
region      = "us-east-1"

# Tags transversales (PC-IAC-004): llaves y valores en minúscula
common_tags = {
  client      = "acme"
  project     = "notif"
  environment = "dev"
  owner       = "cloudops-team"
  costcenter  = "cc-0001"
}

# Remitente delegado cross-account (cuenta externa: no se puede consultar con data sources)
# El ARN del rol NO se escribe: locals.tf lo arma con la convención del módulo IAM de somospragma.
# Resultado: arn:aws:iam::222222222222:role/service-role/acme-billing-dev-role-lambda-billing-invoice-sender
delegated_senders = {
  "invoice-sender" = {
    account_id    = "222222222222"
    client        = "acme"
    project       = "billing"
    environment   = "dev"
    service       = "lambda"
    application   = "billing"
    functionality = "invoice-sender"
    path          = "/service-role/"
  }
}

# Topic SNS existente: acme-notif-dev-sns-ses-events (módulo SNS de somospragma)
ses_events_sns_topic_key = "ses-events"

ses_identities_config = {
  "main" = {
    identity                = "example.com"
    identity_type           = "DOMAIN"
    dkim_signing_key_length = "RSA_2048_BIT"
    configuration_set_key   = "default"

    mail_from = {
      domain                 = "mail.example.com"
      behavior_on_mx_failure = "USE_DEFAULT_VALUE"
    }

    sending_authorization = {
      "AllowInvoiceSender" = {
        delegated_sender_key   = "invoice-sender" # principals se inyecta en locals.tf
        allowed_from_addresses = ["no-reply@example.com"]
      }
    }

    additional_tags = {
      functionality = "transactional-email"
      domain        = "workload"
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

    additional_tags = {
      functionality = "transactional-email"
      domain        = "workload"
    }
  }
}
