# Valores locales y transformaciones (PC-IAC-003, PC-IAC-009, PC-IAC-012)
locals {
  # 1. Prefijo base de gobernanza (PC-IAC-003)
  governance_prefix = "${var.client}-${var.project}-${var.environment}"

  # 2. Etiquetas base del módulo (PC-IAC-004, PC-IAC-012)
  base_module_tags = {
    ManagedBy = "terraform"
    Module    = "ses-module"
  }

  # 3. Constantes del servicio (registros DNS documentados por AWS SES)
  dns_record_ttl   = 1800
  spf_record_value = "v=spf1 include:amazonses.com ~all"
  dmarc_suggested  = "v=DMARC1; p=none;"

  # 4. Nombres de configuration sets (PC-IAC-003, PC-IAC-025)
  # Usa el nombre final inyectado por el Root; si viene vacío: {governance_prefix}-ses-{key}
  configuration_set_names = {
    for key, config in var.ses_configuration_sets_config :
    key => length(config.configuration_set_name) > 0 ? config.configuration_set_name : "${local.governance_prefix}-ses-${key}"
  }

  # 5. Nombres de políticas de sending authorization (una por identidad con statements)
  identity_policy_names = {
    for key, config in var.ses_identities_config :
    key => length(config.policy_name) > 0 ? config.policy_name : "${local.governance_prefix}-ses-${key}"
    if length(config.sending_authorization) > 0
  }

  # 6. Identidades con MAIL FROM personalizado (solo DOMAIN, validado en variables.tf)
  mail_from_map = {
    for key, config in var.ses_identities_config :
    key => config
    if config.mail_from != null
  }

  # 7. Aplanamiento de event destinations (PC-IAC-012) y mapa para for_each (PC-IAC-010)
  event_destinations_flat = flatten([
    for cs_key, cs_config in var.ses_configuration_sets_config : [
      for dest_key, dest_config in cs_config.event_destinations : {
        composite_key         = "${cs_key}-${dest_key}"
        configuration_set_key = cs_key
        name                  = length(dest_config.event_destination_name) > 0 ? dest_config.event_destination_name : "${local.governance_prefix}-ses-${dest_key}"
        enabled               = dest_config.enabled
        matching_event_types  = dest_config.matching_event_types
        sns_topic_arn         = dest_config.sns_topic_arn
        event_bus_arn         = dest_config.event_bus_arn
        cloudwatch_dimensions = dest_config.cloudwatch_dimensions
      }
    ]
  ])

  event_destinations_map = {
    for dest in local.event_destinations_flat : dest.composite_key => dest
  }

  # 8. Detección de principals de otra cuenta por statement (PC-IAC-020)
  cross_account_statements_without_from = flatten([
    for key, config in var.ses_identities_config : [
      for sid, statement in config.sending_authorization : "${key}/${sid}"
      if length(statement.allowed_from_addresses) == 0 && anytrue([
        for principal in statement.principals :
        try(regex("^arn:aws[a-z-]*:iam::([0-9]{12}):", principal)[0], "") != var.account_id
      ])
    ]
  ])

  # 9. Documentos de política de sending authorization (PC-IAC-009)
  # Las condiciones vacías se omiten del documento.
  identity_policy_documents = {
    for key, name in local.identity_policy_names :
    key => jsonencode({
      Version = "2012-10-17"
      Statement = [
        for sid, statement in var.ses_identities_config[key].sending_authorization : merge(
          {
            Sid       = sid
            Effect    = "Allow"
            Principal = { AWS = statement.principals }
            Action    = statement.actions
            Resource  = aws_sesv2_email_identity.this[key].arn
          },
          {
            for cond_key, cond_value in {
              Condition = {
                StringEquals = {
                  for cond_name, cond_values in {
                    "ses:FromAddress"   = statement.allowed_from_addresses
                    "aws:SourceAccount" = statement.source_accounts
                  } : cond_name => cond_values
                  if length(cond_values) > 0
                }
              }
            } : cond_key => cond_value
            if length(statement.allowed_from_addresses) + length(statement.source_accounts) > 0
          }
        )
      ]
    })
  }

  # 10. Registros DNS requeridos por identidad DOMAIN (output dns_records)
  # DKIM (3 CNAME), MAIL FROM (MX + TXT SPF) y DMARC sugerido.
  dns_records = {
    for key, config in var.ses_identities_config :
    key => config.identity_type != "DOMAIN" ? [] : concat(
      [
        for token in try(aws_sesv2_email_identity.this[key].dkim_signing_attributes[0].tokens, []) : {
          name  = "${token}._domainkey.${config.identity}"
          type  = "CNAME"
          ttl   = local.dns_record_ttl
          value = "${token}.dkim.amazonses.com"
        }
      ],
      config.mail_from == null ? [] : [
        {
          name  = config.mail_from.domain
          type  = "MX"
          ttl   = local.dns_record_ttl
          value = "10 feedback-smtp.${aws_sesv2_email_identity.this[key].region}.amazonses.com"
        },
        {
          name  = config.mail_from.domain
          type  = "TXT"
          ttl   = local.dns_record_ttl
          value = local.spf_record_value
        }
      ],
      [
        {
          name  = "_dmarc.${config.identity}"
          type  = "TXT"
          ttl   = local.dns_record_ttl
          value = local.dmarc_suggested
        }
      ]
    )
  }
}
