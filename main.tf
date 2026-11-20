# Recursos principales del módulo SES API v2 (PC-IAC-010, PC-IAC-014, PC-IAC-020, PC-IAC-023)

# =============================================================================
# SES Configuration Sets (PC-IAC-010: for_each obligatorio)
# =============================================================================

resource "aws_sesv2_configuration_set" "this" {
  for_each = var.ses_configuration_sets_config
  provider = aws.project # PC-IAC-005

  # Nomenclatura construida en locals.tf (PC-IAC-003, PC-IAC-025)
  configuration_set_name = local.configuration_set_names[each.key]

  # Hardenizado: cifrado en tránsito TLS obligatorio por defecto (PC-IAC-020)
  delivery_options {
    tls_policy = each.value.tls_policy
  }

  reputation_options {
    reputation_metrics_enabled = each.value.reputation_metrics_enabled
  }

  sending_options {
    sending_enabled = each.value.sending_enabled
  }

  suppression_options {
    suppressed_reasons = each.value.suppressed_reasons
  }

  # Tags (PC-IAC-004): Name + tags base del módulo + additional_tags
  tags = merge(
    local.base_module_tags,
    {
      Name          = local.configuration_set_names[each.key]
      Functionality = each.value.functionality
    },
    each.value.additional_tags
  )

  lifecycle {
    precondition {
      condition     = length(local.configuration_set_names[each.key]) <= 28
      error_message = "Configuration set name '${local.configuration_set_names[each.key]}' exceeds 28 characters (PC-IAC-003). Shorten client/project or the map key."
    }
  }
}

# =============================================================================
# SES Configuration Set Event Destinations (PC-IAC-010, PC-IAC-014)
# =============================================================================

resource "aws_sesv2_configuration_set_event_destination" "this" {
  for_each = local.event_destinations_map
  provider = aws.project # PC-IAC-005

  configuration_set_name = aws_sesv2_configuration_set.this[each.value.configuration_set_key].configuration_set_name
  event_destination_name = each.value.name

  event_destination {
    enabled              = each.value.enabled
    matching_event_types = each.value.matching_event_types

    # Bloques dinámicos: exactamente un destino (validado en variables.tf) (PC-IAC-014)
    dynamic "sns_destination" {
      for_each = length(each.value.sns_topic_arn) > 0 ? [each.value.sns_topic_arn] : []
      content {
        topic_arn = sns_destination.value
      }
    }

    dynamic "event_bridge_destination" {
      for_each = length(each.value.event_bus_arn) > 0 ? [each.value.event_bus_arn] : []
      content {
        event_bus_arn = event_bridge_destination.value
      }
    }

    dynamic "cloud_watch_destination" {
      for_each = length(each.value.cloudwatch_dimensions) > 0 ? [each.value.cloudwatch_dimensions] : []
      content {
        dynamic "dimension_configuration" {
          for_each = cloud_watch_destination.value
          content {
            dimension_name          = dimension_configuration.value.dimension_name
            dimension_value_source  = dimension_configuration.value.dimension_value_source
            default_dimension_value = dimension_configuration.value.default_dimension_value
          }
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = length(each.value.name) <= 28
      error_message = "Event destination name '${each.value.name}' exceeds 28 characters (PC-IAC-003). Shorten client/project or the destination key."
    }
  }
}

# =============================================================================
# SES Email Identities (dominio o correo real, sin prefijo de gobernanza)
# =============================================================================

resource "aws_sesv2_email_identity" "this" {
  for_each = var.ses_identities_config
  provider = aws.project # PC-IAC-005

  email_identity = each.value.identity

  # Configuration set por defecto (PC-IAC-009: length() + ternario, try() para keys inexistentes)
  configuration_set_name = length(each.value.configuration_set_key) > 0 ? try(aws_sesv2_configuration_set.this[each.value.configuration_set_key].configuration_set_name, null) : null

  # Hardenizado: Easy DKIM con 2048 bits por defecto, solo identidades DOMAIN (PC-IAC-020)
  dynamic "dkim_signing_attributes" {
    for_each = each.value.identity_type == "DOMAIN" ? [each.value.dkim_signing_key_length] : []
    content {
      next_signing_key_length = dkim_signing_attributes.value
    }
  }

  # Tags (PC-IAC-004): Name + tags base del módulo + additional_tags
  tags = merge(
    local.base_module_tags,
    {
      Name          = each.value.identity
      Functionality = each.value.functionality
    },
    each.value.additional_tags
  )

  lifecycle {
    # Recurso crítico: recrear la identidad genera nuevos tokens DKIM, rompe el DNS
    # publicado y pierde la verificación (PC-IAC-010)
    prevent_destroy = true

    precondition {
      condition     = length(each.value.configuration_set_key) == 0 || contains(keys(var.ses_configuration_sets_config), each.value.configuration_set_key)
      error_message = "configuration_set_key '${each.value.configuration_set_key}' of identity '${each.key}' does not exist in ses_configuration_sets_config."
    }
  }
}

# =============================================================================
# SES Custom MAIL FROM (solo identidades DOMAIN)
# =============================================================================

resource "aws_sesv2_email_identity_mail_from_attributes" "this" {
  for_each = local.mail_from_map
  provider = aws.project # PC-IAC-005

  email_identity         = aws_sesv2_email_identity.this[each.key].email_identity
  mail_from_domain       = each.value.mail_from.domain
  behavior_on_mx_failure = each.value.mail_from.behavior_on_mx_failure
}

# =============================================================================
# SES Sending Authorization Policy (una por identidad)
# =============================================================================

resource "aws_sesv2_email_identity_policy" "this" {
  for_each = local.identity_policy_names
  provider = aws.project # PC-IAC-005

  email_identity = aws_sesv2_email_identity.this[each.key].email_identity
  policy_name    = each.value
  policy         = local.identity_policy_documents[each.key]

  lifecycle {
    precondition {
      condition     = length(each.value) <= 28
      error_message = "Identity policy name '${each.value}' exceeds 28 characters (PC-IAC-003). Shorten client/project or the map key."
    }

    # Hardenizado: principals de otra cuenta exigen ses:FromAddress (PC-IAC-020)
    precondition {
      condition     = length([for item in local.cross_account_statements_without_from : item if startswith(item, "${each.key}/")]) == 0
      error_message = "Identity '${each.key}': sending_authorization statements with principals outside account ${var.account_id} must define a non-empty allowed_from_addresses (PC-IAC-020)."
    }
  }
}
