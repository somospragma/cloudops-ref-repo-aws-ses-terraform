# Pruebas automatizadas del módulo SES (PC-IAC-018)
# Ejecutar desde la raíz del módulo: terraform init && terraform test
# Usan un provider mock: no requieren credenciales ni crean recursos.
# Todas las pruebas son "plan" (prevent_destroy en la identidad impide destruir en teardown).

mock_provider "aws" {
  alias           = "project"
  override_during = plan

  override_resource {
    target = aws_sesv2_email_identity.this["pragma"]
    values = {
      arn                     = "arn:aws:ses:us-east-1:654767188854:identity/pragma.com.co"
      region                  = "us-east-1"
      dkim_signing_attributes = { tokens = ["tok1", "tok2", "tok3"] }
    }
  }
}

variables {
  client      = "pragma"
  project     = "notif"
  environment = "pdn"
  account_id  = "654767188854"

  ses_identities_config = {
    "pragma" = {
      identity              = "pragma.com.co"
      identity_type         = "DOMAIN"
      configuration_set_key = "default"
      mail_from             = { domain = "mail.pragma.com.co" }
      sending_authorization = {
        "AllowLicenseProcessingLambda" = {
          principals             = ["arn:aws:iam::533267042257:role/service-role/pragma-license-pdn-role-lambda-license-license-processing"]
          allowed_from_addresses = ["licenciasgenia@pragma.com.co"]
        }
      }
      functionality = "transactional-email"
    }
  }

  ses_configuration_sets_config = {
    "default" = {
      event_destinations = {
        "events" = {
          matching_event_types = ["BOUNCE", "COMPLAINT"]
          sns_topic_arn        = "arn:aws:sns:us-east-1:654767188854:pragma-notif-pdn-sns-ses-events"
        }
      }
      functionality = "transactional-email"
    }
  }
}

# ── Caso feliz ──

run "naming_and_security_defaults" {
  command = plan

  assert {
    condition     = aws_sesv2_configuration_set.this["default"].configuration_set_name == "pragma-notif-pdn-ses-default"
    error_message = "Configuration set name must follow {client}-{project}-{environment}-ses-{key} (PC-IAC-003)."
  }

  assert {
    condition     = aws_sesv2_configuration_set_event_destination.this["default-events"].event_destination_name == "pragma-notif-pdn-ses-events"
    error_message = "Event destination name must follow {client}-{project}-{environment}-ses-{key} (PC-IAC-003)."
  }

  assert {
    condition     = aws_sesv2_email_identity_policy.this["pragma"].policy_name == "pragma-notif-pdn-ses-pragma"
    error_message = "Policy name must follow {client}-{project}-{environment}-ses-{key} (PC-IAC-003)."
  }

  assert {
    condition     = aws_sesv2_email_identity.this["pragma"].email_identity == "pragma.com.co"
    error_message = "Identity must keep the real domain without governance prefix."
  }

  assert {
    condition     = aws_sesv2_configuration_set.this["default"].delivery_options[0].tls_policy == "REQUIRE"
    error_message = "TLS must be REQUIRE by default (PC-IAC-020)."
  }

  assert {
    condition     = aws_sesv2_email_identity.this["pragma"].dkim_signing_attributes[0].next_signing_key_length == "RSA_2048_BIT"
    error_message = "DKIM must default to RSA_2048_BIT (PC-IAC-020)."
  }

  assert {
    condition     = toset(aws_sesv2_configuration_set.this["default"].suppression_options[0].suppressed_reasons) == toset(["BOUNCE", "COMPLAINT"])
    error_message = "Suppression must default to BOUNCE and COMPLAINT."
  }

  assert {
    condition     = aws_sesv2_email_identity.this["pragma"].tags["ManagedBy"] == "terraform" && aws_sesv2_email_identity.this["pragma"].tags["Module"] == "ses-module" && aws_sesv2_email_identity.this["pragma"].tags["Name"] == "pragma.com.co"
    error_message = "Module tags Name, ManagedBy and Module must be applied (PC-IAC-004)."
  }

  assert {
    condition     = aws_sesv2_email_identity.this["pragma"].configuration_set_name == "pragma-notif-pdn-ses-default"
    error_message = "Identity must use the referenced configuration set by default."
  }
}

run "policy_document" {
  command = plan

  assert {
    condition     = jsondecode(aws_sesv2_email_identity_policy.this["pragma"].policy).Statement[0].Sid == "AllowLicenseProcessingLambda"
    error_message = "Statement Sid must be the sending_authorization key."
  }

  assert {
    condition     = jsondecode(aws_sesv2_email_identity_policy.this["pragma"].policy).Statement[0].Resource == "arn:aws:ses:us-east-1:654767188854:identity/pragma.com.co"
    error_message = "Policy resource must be the identity ARN."
  }

  assert {
    condition     = jsondecode(aws_sesv2_email_identity_policy.this["pragma"].policy).Statement[0].Condition.StringEquals["ses:FromAddress"] == ["licenciasgenia@pragma.com.co"]
    error_message = "Policy must restrict ses:FromAddress."
  }

  assert {
    condition     = !can(jsondecode(aws_sesv2_email_identity_policy.this["pragma"].policy).Statement[0].Condition.StringEquals["aws:SourceAccount"])
    error_message = "Empty source_accounts must not generate an aws:SourceAccount condition."
  }
}

run "dns_records_output" {
  command = plan

  assert {
    condition     = length(output.dns_records["pragma"]) == 6
    error_message = "Expected 3 DKIM CNAME + MX + SPF TXT + DMARC TXT."
  }

  assert {
    condition     = output.dns_records["pragma"][0].name == "tok1._domainkey.pragma.com.co" && output.dns_records["pragma"][0].value == "tok1.dkim.amazonses.com"
    error_message = "Bad DKIM CNAME record."
  }

  assert {
    condition     = output.dns_records["pragma"][3].type == "MX" && output.dns_records["pragma"][3].value == "10 feedback-smtp.us-east-1.amazonses.com"
    error_message = "Bad MAIL FROM MX record."
  }

  assert {
    condition     = output.dns_records["pragma"][4].value == "v=spf1 include:amazonses.com ~all"
    error_message = "Bad SPF record."
  }

  assert {
    condition     = output.dns_records["pragma"][5].name == "_dmarc.pragma.com.co"
    error_message = "Bad DMARC record."
  }
}

run "root_injected_names" {
  command = plan

  variables {
    ses_configuration_sets_config = {
      "default" = {
        configuration_set_name = "pragma-notif-pdn-ses-main"
        functionality          = "x"
      }
    }
  }

  assert {
    condition     = aws_sesv2_configuration_set.this["default"].configuration_set_name == "pragma-notif-pdn-ses-main"
    error_message = "Root-injected name must be used as-is (PC-IAC-025)."
  }
}

run "same_account_without_from_allowed" {
  command = plan

  variables {
    ses_identities_config = {
      "pragma" = {
        identity              = "pragma.com.co"
        identity_type         = "DOMAIN"
        functionality         = "x"
        sending_authorization = { "SameAccount" = { principals = ["arn:aws:iam::654767188854:role/app"] } }
      }
    }
  }

  assert {
    condition     = !can(jsondecode(aws_sesv2_email_identity_policy.this["pragma"].policy).Statement[0].Condition)
    error_message = "Statements without conditions must omit Condition."
  }
}

run "email_identity_without_dns" {
  command = plan

  variables {
    ses_identities_config = {
      "ops" = { identity = "ops@pragma.com.co", identity_type = "EMAIL", functionality = "x" }
    }
  }

  assert {
    condition     = length(output.dns_records["ops"]) == 0
    error_message = "EMAIL identities must not produce DNS records."
  }

  assert {
    condition     = length(aws_sesv2_email_identity.this["ops"].dkim_signing_attributes) == 0
    error_message = "EMAIL identities must not configure Easy DKIM."
  }
}

run "cloudwatch_destination" {
  command = plan

  variables {
    ses_configuration_sets_config = {
      "default" = {
        functionality = "x"
        event_destinations = {
          "metrics" = {
            matching_event_types  = ["SEND", "DELIVERY"]
            cloudwatch_dimensions = [{ dimension_name = "app", dimension_value_source = "MESSAGE_TAG", default_dimension_value = "none" }]
          }
        }
      }
    }
  }

  assert {
    condition     = length(aws_sesv2_configuration_set_event_destination.this["default-metrics"].event_destination[0].cloud_watch_destination) == 1
    error_message = "CloudWatch destination must be configured."
  }
}

# ── Validaciones de seguridad (PC-IAC-020) ──

run "reject_cross_account_without_from" {
  command = plan

  variables {
    ses_identities_config = {
      "pragma" = {
        identity              = "pragma.com.co"
        identity_type         = "DOMAIN"
        functionality         = "x"
        sending_authorization = { "Other" = { principals = ["arn:aws:iam::533267042257:role/app"] } }
      }
    }
  }

  expect_failures = [aws_sesv2_email_identity_policy.this]
}

run "reject_wildcard_principal" {
  command = plan

  variables {
    ses_identities_config = {
      "pragma" = {
        identity              = "pragma.com.co"
        identity_type         = "DOMAIN"
        functionality         = "x"
        sending_authorization = { "Any" = { principals = ["*"], allowed_from_addresses = ["a@pragma.com.co"] } }
      }
    }
  }

  expect_failures = [var.ses_identities_config]
}

run "reject_wildcard_action" {
  command = plan

  variables {
    ses_identities_config = {
      "pragma" = {
        identity              = "pragma.com.co"
        identity_type         = "DOMAIN"
        functionality         = "x"
        sending_authorization = { "Any" = { principals = ["arn:aws:iam::654767188854:root"], actions = ["ses:*"] } }
      }
    }
  }

  expect_failures = [var.ses_identities_config]
}

run "reject_from_address_wildcard" {
  command = plan

  variables {
    ses_identities_config = {
      "pragma" = {
        identity              = "pragma.com.co"
        identity_type         = "DOMAIN"
        functionality         = "x"
        sending_authorization = { "X" = { principals = ["arn:aws:iam::533267042257:root"], allowed_from_addresses = ["*@pragma.com.co"] } }
      }
    }
  }

  expect_failures = [var.ses_identities_config]
}

run "reject_from_address_other_domain" {
  command = plan

  variables {
    ses_identities_config = {
      "pragma" = {
        identity              = "pragma.com.co"
        identity_type         = "DOMAIN"
        functionality         = "x"
        sending_authorization = { "X" = { principals = ["arn:aws:iam::533267042257:root"], allowed_from_addresses = ["a@evil.com"] } }
      }
    }
  }

  expect_failures = [var.ses_identities_config]
}

run "reject_tls_optional_without_flag" {
  command = plan

  variables {
    ses_configuration_sets_config = { "default" = { tls_policy = "OPTIONAL", functionality = "x" } }
  }

  expect_failures = [var.ses_configuration_sets_config]
}

run "allow_tls_optional_with_flag" {
  command = plan

  variables {
    ses_configuration_sets_config = { "default" = { tls_policy = "OPTIONAL", allow_optional_tls = true, functionality = "x" } }
  }

  assert {
    condition     = aws_sesv2_configuration_set.this["default"].delivery_options[0].tls_policy == "OPTIONAL"
    error_message = "OPTIONAL TLS must be allowed with the explicit flag."
  }
}

# ── Validaciones de formato ──

run "reject_mail_from_not_subdomain" {
  command = plan

  variables {
    ses_identities_config = {
      "pragma" = { identity = "pragma.com.co", identity_type = "DOMAIN", functionality = "x", mail_from = { domain = "mail.otro.com" } }
    }
  }

  expect_failures = [var.ses_identities_config]
}

run "reject_mail_from_on_email_identity" {
  command = plan

  variables {
    ses_identities_config = {
      "ops" = { identity = "ops@pragma.com.co", identity_type = "EMAIL", functionality = "x", mail_from = { domain = "mail.pragma.com.co" } }
    }
  }

  expect_failures = [var.ses_identities_config]
}

run "reject_invalid_identity_type" {
  command = plan

  variables {
    ses_identities_config = {
      "pragma" = { identity = "pragma.com.co", identity_type = "EMAIL_ADDRESS", functionality = "x" }
    }
  }

  expect_failures = [var.ses_identities_config]
}

run "reject_invalid_domain" {
  command = plan

  variables {
    ses_identities_config = {
      "pragma" = { identity = "not a domain", identity_type = "DOMAIN", functionality = "x" }
    }
  }

  expect_failures = [var.ses_identities_config]
}

run "reject_invalid_dkim_length" {
  command = plan

  variables {
    ses_identities_config = {
      "pragma" = { identity = "pragma.com.co", identity_type = "DOMAIN", functionality = "x", dkim_signing_key_length = "RSA_4096_BIT" }
    }
  }

  expect_failures = [var.ses_identities_config]
}

run "reject_invalid_event_type" {
  command = plan

  variables {
    ses_configuration_sets_config = {
      "default" = {
        functionality      = "x"
        event_destinations = { "a" = { matching_event_types = ["BOUNCES"], event_bus_arn = "arn:aws:events:us-east-1:654767188854:event-bus/default" } }
      }
    }
  }

  expect_failures = [var.ses_configuration_sets_config]
}

run "reject_two_destinations" {
  command = plan

  variables {
    ses_configuration_sets_config = {
      "default" = {
        functionality = "x"
        event_destinations = {
          "a" = {
            matching_event_types = ["BOUNCE"]
            sns_topic_arn        = "arn:aws:sns:us-east-1:654767188854:t"
            event_bus_arn        = "arn:aws:events:us-east-1:654767188854:event-bus/default"
          }
        }
      }
    }
  }

  expect_failures = [var.ses_configuration_sets_config]
}

run "reject_missing_configuration_set_key" {
  command = plan

  variables {
    ses_identities_config = {
      "pragma" = { identity = "pragma.com.co", identity_type = "DOMAIN", functionality = "x", configuration_set_key = "nope" }
    }
  }

  expect_failures = [aws_sesv2_email_identity.this]
}

run "reject_name_longer_than_28" {
  command = plan

  variables {
    project = "notificaciones"
  }

  expect_failures = [aws_sesv2_configuration_set.this]
}

run "reject_invalid_account_id" {
  command = plan

  variables {
    account_id = "123"
  }

  expect_failures = [var.account_id]
}

run "reject_invalid_environment" {
  command = plan

  variables {
    environment = "production"
  }

  expect_failures = [var.environment]
}
