# Variables de entrada del módulo (PC-IAC-002, PC-IAC-009, PC-IAC-016, PC-IAC-023, PC-IAC-024)

###########################################
### Variables de Gobernanza (PC-IAC-002) ###
###########################################

variable "client" {
  description = "Client name for resource naming (PC-IAC-003)"
  type        = string

  validation {
    condition     = length(var.client) > 0 && length(var.client) <= 10
    error_message = "Client name must be between 1 and 10 characters."
  }

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.client))
    error_message = "Client name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project" {
  description = "Project name for resource naming (PC-IAC-003)"
  type        = string

  validation {
    condition     = length(var.project) > 0 && length(var.project) <= 15
    error_message = "Project name must be between 1 and 15 characters."
  }

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment where resources will be deployed"
  type        = string

  validation {
    condition     = contains(["dev", "qa", "stg", "pdn", "prod"], var.environment)
    error_message = "Environment must be one of: dev, qa, stg, pdn, prod."
  }
}

###########################################
## Variables Transversales (PC-IAC-011) ###
###########################################

variable "account_id" {
  description = "AWS account ID that owns the SES identities. Injected from the Root (e.g. data.aws_caller_identity.current.account_id). Used to detect cross-account principals in sending authorization (PC-IAC-020)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

###########################################
### Variables de Configuración SES ########
###########################################

variable "ses_identities_config" {
  description = <<-EOT
    Map of SES (API v2) email identities. The map key is the logical identifier used to name
    the identity policy ({client}-{project}-{environment}-ses-{key}) and in outputs.
    The identity itself is NOT prefixed: it is the real domain or email address.
  EOT
  type = map(object({
    identity                = string                           # Domain (pragma.com.co) or email (user@pragma.com.co)
    identity_type           = string                           # DOMAIN | EMAIL
    dkim_signing_key_length = optional(string, "RSA_2048_BIT") # Easy DKIM (DOMAIN only): RSA_1024_BIT | RSA_2048_BIT
    configuration_set_key   = optional(string, "")             # Key in ses_configuration_sets_config used by default
    policy_name             = optional(string, "")             # Final policy name injected by the Root (PC-IAC-025)

    # Custom MAIL FROM domain (DOMAIN only). Must be a subdomain of identity.
    mail_from = optional(object({
      domain                 = string
      behavior_on_mx_failure = optional(string, "USE_DEFAULT_VALUE") # USE_DEFAULT_VALUE | REJECT_MESSAGE
    }))

    # Sending authorization statements. Map key = statement Sid (PC-IAC-002: map for stability)
    sending_authorization = optional(map(object({
      principals             = list(string) # arn:aws:iam::<account>:root | arn:aws:iam::<account>:role/<name>
      actions                = optional(list(string), ["ses:SendEmail", "ses:SendRawEmail"])
      allowed_from_addresses = optional(list(string), []) # Condition ses:FromAddress
      source_accounts        = optional(list(string), []) # Condition aws:SourceAccount
    })), {})

    functionality   = string
    additional_tags = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.ses_identities_config :
      can(regex("^[a-z0-9-]+$", k)) && length(k) <= 20
    ])
    error_message = "ses_identities_config keys must contain only lowercase letters, numbers, and hyphens (max 20 characters, PC-IAC-003)."
  }

  validation {
    condition = alltrue([
      for k, v in var.ses_identities_config :
      contains(["DOMAIN", "EMAIL"], v.identity_type)
    ])
    error_message = "identity_type must be either 'DOMAIN' or 'EMAIL'."
  }

  validation {
    condition = alltrue([
      for k, v in var.ses_identities_config :
      v.identity_type == "DOMAIN"
      ? can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", v.identity))
      : can(regex("^[A-Za-z0-9._%+-]+@([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", v.identity))
    ])
    error_message = "identity must be a valid lowercase domain (identity_type = DOMAIN) or a valid email address (identity_type = EMAIL)."
  }

  validation {
    condition = alltrue([
      for k, v in var.ses_identities_config :
      contains(["RSA_1024_BIT", "RSA_2048_BIT"], v.dkim_signing_key_length)
    ])
    error_message = "dkim_signing_key_length must be either 'RSA_1024_BIT' or 'RSA_2048_BIT'."
  }

  validation {
    condition = alltrue([
      for k, v in var.ses_identities_config :
      length(v.policy_name) == 0 || (can(regex("^[a-z0-9-]+$", v.policy_name)) && length(v.policy_name) <= 28)
    ])
    error_message = "policy_name must contain only lowercase letters, numbers, and hyphens (max 28 characters, PC-IAC-003)."
  }

  # ── MAIL FROM validations ──
  validation {
    condition = alltrue([
      for k, v in var.ses_identities_config :
      v.mail_from == null || v.identity_type == "DOMAIN"
    ])
    error_message = "mail_from is only supported for identities with identity_type = DOMAIN."
  }

  validation {
    condition = alltrue([
      for k, v in var.ses_identities_config :
      v.mail_from == null || try(endswith(v.mail_from.domain, ".${v.identity}"), false)
    ])
    error_message = "mail_from.domain must be a subdomain of identity (e.g. mail.pragma.com.co for pragma.com.co)."
  }

  validation {
    condition = alltrue([
      for k, v in var.ses_identities_config :
      v.mail_from == null || try(contains(["USE_DEFAULT_VALUE", "REJECT_MESSAGE"], v.mail_from.behavior_on_mx_failure), false)
    ])
    error_message = "mail_from.behavior_on_mx_failure must be either 'USE_DEFAULT_VALUE' or 'REJECT_MESSAGE'."
  }

  # ── Sending authorization validations (PC-IAC-020) ──
  validation {
    condition = alltrue(flatten([
      for k, v in var.ses_identities_config : [
        for sid, s in v.sending_authorization :
        can(regex("^[A-Za-z0-9]+$", sid))
      ]
    ]))
    error_message = "sending_authorization keys are used as policy Sid and must be alphanumeric."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.ses_identities_config : [
        for sid, s in v.sending_authorization :
        length(s.principals) > 0 && alltrue([
          for p in s.principals :
          can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(root|role/[A-Za-z0-9+=,.@_/-]+)$", p))
        ])
      ]
    ]))
    error_message = "sending_authorization.principals must be a non-empty list of account (arn:aws:iam::<12 digits>:root) or role (arn:aws:iam::<12 digits>:role/<name>) ARNs. Wildcards are not allowed (PC-IAC-020)."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.ses_identities_config : [
        for sid, s in v.sending_authorization :
        length(s.actions) > 0 && alltrue([
          for a in s.actions :
          contains(["ses:SendEmail", "ses:SendRawEmail", "ses:SendTemplatedEmail", "ses:SendBulkTemplatedEmail", "ses:SendBulkEmail"], a)
        ])
      ]
    ]))
    error_message = "sending_authorization.actions must be a non-empty subset of: ses:SendEmail, ses:SendRawEmail, ses:SendTemplatedEmail, ses:SendBulkTemplatedEmail, ses:SendBulkEmail. Wildcards are not allowed (PC-IAC-020)."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.ses_identities_config : [
        for sid, s in v.sending_authorization : [
          for addr in s.allowed_from_addresses :
          can(regex("^[A-Za-z0-9._%+-]+@[a-z0-9.-]+$", addr)) && (
            v.identity_type == "DOMAIN"
            ? (endswith(addr, "@${v.identity}") || endswith(addr, ".${v.identity}"))
            : addr == v.identity
          )
        ]
      ]
    ]))
    error_message = "sending_authorization.allowed_from_addresses must be explicit email addresses (no wildcards) that belong to the identity domain, or equal to the identity for EMAIL identities."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.ses_identities_config : [
        for sid, s in v.sending_authorization : [
          for acc in s.source_accounts :
          can(regex("^[0-9]{12}$", acc))
        ]
      ]
    ]))
    error_message = "sending_authorization.source_accounts must contain 12-digit AWS account IDs."
  }
}

variable "ses_configuration_sets_config" {
  description = "Map of SES (API v2) configuration sets. The map key builds the name {client}-{project}-{environment}-ses-{key} unless the Root injects configuration_set_name (PC-IAC-025)."
  type = map(object({
    configuration_set_name     = optional(string, "")        # Final name injected by the Root (PC-IAC-025)
    tls_policy                 = optional(string, "REQUIRE") # REQUIRE | OPTIONAL
    allow_optional_tls         = optional(bool, false)       # Explicit flag required to use tls_policy = OPTIONAL
    reputation_metrics_enabled = optional(bool, true)
    sending_enabled            = optional(bool, true)
    suppressed_reasons         = optional(list(string), ["BOUNCE", "COMPLAINT"])

    # Event destinations. Map key builds the destination name (PC-IAC-002: map for stability)
    event_destinations = optional(map(object({
      event_destination_name = optional(string, "") # Final name injected by the Root (PC-IAC-025)
      enabled                = optional(bool, true)
      matching_event_types   = list(string)
      sns_topic_arn          = optional(string, "")
      event_bus_arn          = optional(string, "")
      cloudwatch_dimensions = optional(list(object({
        dimension_name          = string
        dimension_value_source  = string # MESSAGE_TAG | EMAIL_HEADER | LINK_TAG
        default_dimension_value = string
      })), [])
    })), {})

    functionality   = string
    additional_tags = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.ses_configuration_sets_config :
      can(regex("^[a-z0-9-]+$", k)) && length(k) <= 20
    ])
    error_message = "ses_configuration_sets_config keys must contain only lowercase letters, numbers, and hyphens (max 20 characters, PC-IAC-003)."
  }

  validation {
    condition = alltrue([
      for k, v in var.ses_configuration_sets_config :
      length(v.configuration_set_name) == 0 || (can(regex("^[a-z0-9-]+$", v.configuration_set_name)) && length(v.configuration_set_name) <= 28)
    ])
    error_message = "configuration_set_name must contain only lowercase letters, numbers, and hyphens (max 28 characters, PC-IAC-003)."
  }

  validation {
    condition = alltrue([
      for k, v in var.ses_configuration_sets_config :
      contains(["REQUIRE", "OPTIONAL"], v.tls_policy)
    ])
    error_message = "tls_policy must be either 'REQUIRE' or 'OPTIONAL'."
  }

  validation {
    condition = alltrue([
      for k, v in var.ses_configuration_sets_config :
      v.tls_policy == "REQUIRE" || v.allow_optional_tls
    ])
    error_message = "tls_policy = OPTIONAL requires allow_optional_tls = true explicitly (PC-IAC-020: TLS in transit by default)."
  }

  validation {
    condition = alltrue([
      for k, v in var.ses_configuration_sets_config :
      alltrue([for r in v.suppressed_reasons : contains(["BOUNCE", "COMPLAINT"], r)])
    ])
    error_message = "suppressed_reasons only supports: BOUNCE, COMPLAINT."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.ses_configuration_sets_config : [
        for dk, d in v.event_destinations :
        can(regex("^[a-z0-9-]+$", dk)) && length(dk) <= 20
      ]
    ]))
    error_message = "event_destinations keys must contain only lowercase letters, numbers, and hyphens (max 20 characters, PC-IAC-003)."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.ses_configuration_sets_config : [
        for dk, d in v.event_destinations :
        length(d.event_destination_name) == 0 || (can(regex("^[a-z0-9-]+$", d.event_destination_name)) && length(d.event_destination_name) <= 28)
      ]
    ]))
    error_message = "event_destination_name must contain only lowercase letters, numbers, and hyphens (max 28 characters, PC-IAC-003)."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.ses_configuration_sets_config : [
        for dk, d in v.event_destinations :
        length(d.matching_event_types) > 0 && alltrue([
          for e in d.matching_event_types :
          contains(["SEND", "REJECT", "BOUNCE", "COMPLAINT", "DELIVERY", "OPEN", "CLICK", "RENDERING_FAILURE", "DELIVERY_DELAY", "SUBSCRIPTION"], e)
        ])
      ]
    ]))
    error_message = "event_destinations.matching_event_types must be a non-empty subset of: SEND, REJECT, BOUNCE, COMPLAINT, DELIVERY, OPEN, CLICK, RENDERING_FAILURE, DELIVERY_DELAY, SUBSCRIPTION."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.ses_configuration_sets_config : [
        for dk, d in v.event_destinations :
        length([
          for configured in [length(d.sns_topic_arn) > 0, length(d.event_bus_arn) > 0, length(d.cloudwatch_dimensions) > 0] :
          configured if configured
        ]) == 1
      ]
    ]))
    error_message = "Each event destination must define exactly one of: sns_topic_arn, event_bus_arn, cloudwatch_dimensions."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.ses_configuration_sets_config : [
        for dk, d in v.event_destinations :
        length(d.sns_topic_arn) == 0 || can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+(\\.fifo)?$", d.sns_topic_arn))
      ]
    ]))
    error_message = "event_destinations.sns_topic_arn must be a valid SNS topic ARN."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.ses_configuration_sets_config : [
        for dk, d in v.event_destinations :
        length(d.event_bus_arn) == 0 || can(regex("^arn:aws[a-z-]*:events:[a-z0-9-]+:[0-9]{12}:event-bus/default$", d.event_bus_arn))
      ]
    ]))
    error_message = "event_destinations.event_bus_arn must be the ARN of the default EventBridge bus (only the default bus is supported by SES)."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.ses_configuration_sets_config : [
        for dk, d in v.event_destinations : [
          for dim in d.cloudwatch_dimensions :
          contains(["MESSAGE_TAG", "EMAIL_HEADER", "LINK_TAG"], dim.dimension_value_source)
        ]
      ]
    ]))
    error_message = "cloudwatch_dimensions.dimension_value_source must be one of: MESSAGE_TAG, EMAIL_HEADER, LINK_TAG."
  }
}
